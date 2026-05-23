import Foundation
import GRDB
import WidgetKit

/// Управляет периодической синхронизацией. Single-flight per source.
@MainActor
final class SyncCoordinator {
    private let db: any DatabaseWriter
    private let now: () -> Date
    private var inFlight: Set<String> = []
    private var timer: Timer?
    private(set) var lastSyncAt: [String: Date] = [:]

    init(db: any DatabaseWriter, now: @escaping () -> Date = Date.init) {
        self.db = db
        self.now = now
    }

    func startTimer(interval: TimeInterval, sources: [(name: String, fetchers: [any Fetcher])]) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                for (name, fetchers) in sources {
                    try? await self.runOnce(source: name, fetchers: fetchers)
                }
            }
        }
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    func runOnce(source: String, fetchers: [any Fetcher]) async throws {
        guard !inFlight.contains(source) else { return }
        inFlight.insert(source)
        defer { inFlight.remove(source) }

        let since = try syncWindowStart(source: source)
        var capturedError: Error?

        for fetcher in fetchers {
            do {
                let result = try await fetcher.fetch(since: since)
                try persist(result)
            } catch {
                capturedError = error
                NSLog("ai-stats sync error [\(source)]: \(error)")
            }
        }

        try recordSyncState(source: source, error: capturedError)
        lastSyncAt[source] = now()
        try? buildAndWriteWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Считает текущие totals за Day/Week/Month из DB, пишет JSON в контейнер виджета.
    private func buildAndWriteWidgetSnapshot() throws {
        let nowDate = now()
        let dayRange = DateUtils.daysRange(endingAt: nowDate, lookback: Period.day.lookbackDays)
        let weekRange = DateUtils.daysRange(endingAt: nowDate, lookback: Period.week.lookbackDays)
        let monthRange = DateUtils.daysRange(endingAt: nowDate, lookback: Period.month.lookbackDays)

        let slices: (WidgetSnapshot.PeriodSlice, WidgetSnapshot.PeriodSlice, WidgetSnapshot.PeriodSlice) = try db.read { db in
            (
                try Self.makeSlice(in: db, days: dayRange),
                try Self.makeSlice(in: db, days: weekRange),
                try Self.makeSlice(in: db, days: monthRange)
            )
        }

        let anyCommits = slices.0.commits + slices.1.commits + slices.2.commits
        let anyRepos = max(slices.0.uniqueRepos, slices.1.uniqueRepos, slices.2.uniqueRepos)

        let snapshot = WidgetSnapshot(
            generatedAt: nowDate,
            day: slices.0,
            week: slices.1,
            month: slices.2,
            githubEnabled: anyCommits > 0 || anyRepos > 0
        )
        try WidgetSnapshotIO.write(snapshot)
    }

    private static func makeSlice(in db: GRDB.Database, days: [String]) throws -> WidgetSnapshot.PeriodSlice {
        let totals = try StatsQueries.aiTotals(in: db, days: days)
        let gh = try StatsQueries.githubTotals(in: db, days: days)
        let models = try StatsQueries.topModels(in: db, days: days, limit: 4)
        return WidgetSnapshot.PeriodSlice(
            aiCost: totals.totalCost,
            aiTokens: totals.totalInputTokens + totals.totalOutputTokens,
            commits: gh.totalCommits,
            uniqueRepos: gh.uniqueRepos,
            topModels: models.map {
                WidgetSnapshot.ModelEntry(
                    model: $0.model,
                    source: $0.source,
                    costUsd: $0.costUsd,
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens
                )
            }
        )
    }

    private func syncWindowStart(source: String) throws -> Date {
        let cal = Calendar(identifier: .gregorian)
        let state = try db.read { db in try SyncStateRow.filter(SyncStateRow.Columns.source == source).fetchOne(db) }
        let lookbackDays = state == nil ? 365 : 7
        return cal.date(byAdding: .day, value: -lookbackDays, to: now())!
    }

    private func persist(_ result: FetchResult) throws {
        try db.write { db in
            switch result {
            case .aiUsage(let payload):
                for row in payload.dayRows { try NeverDecreaseUpserter.upsertAIUsage(row, in: db) }
                for row in payload.modelRows { try NeverDecreaseUpserter.upsertAIUsageModel(row, in: db) }
            case .github(let payload):
                for row in payload.dailyCommits { try NeverDecreaseUpserter.upsertGitHub(row, in: db) }
                for row in payload.dailyLOC { try NeverDecreaseUpserter.upsertGitHubLOCDaily(row, in: db) }
            }
        }
    }

    private func recordSyncState(source: String, error: Error?) throws {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: now())
        let state = SyncStateRow(source: source, lastSyncAt: nowString, lastError: error?.localizedDescription)
        try db.write { db in
            try state.save(db)
        }
    }
}
