import Foundation
import GRDB
import WidgetKit

/// Управляет периодической синхронизацией. Single-flight per source.
@MainActor
final class SyncCoordinator {
    private let db: any DatabaseWriter
    private let now: () -> Date
    private let snapshotSyncer: SnapshotSyncer?
    private let friendsPullSyncer: FriendsPullSyncer?
    private let leaderboardPullSyncer: LeaderboardPullSyncer?
    private var inFlight: Set<String> = []
    private var timer: Timer?
    private(set) var lastSyncAt: [String: Date] = [:]

    init(db: any DatabaseWriter,
         snapshotSyncer: SnapshotSyncer? = nil,
         friendsPullSyncer: FriendsPullSyncer? = nil,
         leaderboardPullSyncer: LeaderboardPullSyncer? = nil,
         now: @escaping () -> Date = Date.init) {
        self.db = db
        self.snapshotSyncer = snapshotSyncer
        self.friendsPullSyncer = friendsPullSyncer
        self.leaderboardPullSyncer = leaderboardPullSyncer
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

        // После ccusage-sync пушим snapshot'ы на aiuse-сервер, потом тянем
        // обновлённый список друзей и лидерборд. Ошибки не ронят общий тик.
        if source == "ccusage" {
            if let syncer = snapshotSyncer {
                do { _ = try await syncer.runOnce() }
                catch { NSLog("ai-stats aiuse snapshot sync error: \(error)") }
            }
            if let pullSyncer = friendsPullSyncer {
                do { _ = try await pullSyncer.runOnce() }
                catch { NSLog("ai-stats aiuse friends pull error: \(error)") }
            }
            if let lbSyncer = leaderboardPullSyncer {
                do { _ = try await lbSyncer.runOnce() }
                catch { NSLog("ai-stats aiuse leaderboard pull error: \(error)") }
            }
        }
    }

    /// Считает текущие totals за Day/Week/Month, prev-cost для дельт, и leaderboard slice.
    /// Пишет JSON в контейнер виджета.
    private func buildAndWriteWidgetSnapshot() throws {
        let nowDate = now()
        let dayDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.day.lookbackDays)
        let weekDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.week.lookbackDays)
        let monthDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.month.lookbackDays)
        let dayPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.day.lookbackDays)
        let weekPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.week.lookbackDays)
        let monthPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.month.lookbackDays)

        struct BuildResult {
            let day: WidgetSnapshot.PeriodSlice
            let week: WidgetSnapshot.PeriodSlice
            let month: WidgetSnapshot.PeriodSlice
            let myFriendCode: String?
        }

        let result: BuildResult = try db.read { db in
            let myCode = try StatsQueries.loadMyProfile(db)?.friendCode
            return BuildResult(
                day: try Self.makeSlice(in: db, days: dayDays, prevDays: dayPrev, leaderboardPeriod: "day", myFriendCode: myCode),
                week: try Self.makeSlice(in: db, days: weekDays, prevDays: weekPrev, leaderboardPeriod: "week", myFriendCode: myCode),
                month: try Self.makeSlice(in: db, days: monthDays, prevDays: monthPrev, leaderboardPeriod: "month", myFriendCode: myCode),
                myFriendCode: myCode
            )
        }

        let anyCommits = result.day.commits + result.week.commits + result.month.commits
        let anyRepos = max(result.day.uniqueRepos, result.week.uniqueRepos, result.month.uniqueRepos)

        let snapshot = WidgetSnapshot(
            generatedAt: nowDate,
            day: result.day,
            week: result.week,
            month: result.month,
            githubEnabled: anyCommits > 0 || anyRepos > 0,
            myFriendCode: result.myFriendCode
        )
        try WidgetSnapshotIO.write(snapshot)
    }

    private static func makeSlice(
        in db: GRDB.Database,
        days: [String],
        prevDays: [String],
        leaderboardPeriod: String,
        myFriendCode: String?
    ) throws -> WidgetSnapshot.PeriodSlice {
        let totals = try StatsQueries.aiTotals(in: db, days: days)
        let totalsPrev = try StatsQueries.aiTotals(in: db, days: prevDays)
        let gh = try StatsQueries.githubTotals(in: db, days: days)
        let models = try StatsQueries.topModels(in: db, days: days, limit: 4)
        let lb = try Self.makeLeaderboardSlice(in: db, period: leaderboardPeriod, myFriendCode: myFriendCode)

        return WidgetSnapshot.PeriodSlice(
            aiCost: totals.totalCost,
            aiCostPrev: totalsPrev.totalCost,
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
            },
            leaderboard: lb
        )
    }

    /// Парсит leaderboard_cache.payload_json в LeaderboardSlice: top-8 entries + meBelow если я ниже.
    private static func makeLeaderboardSlice(
        in db: GRDB.Database, period: String, myFriendCode: String?
    ) throws -> WidgetSnapshot.LeaderboardSlice? {
        guard let row = try StatsQueries.loadLeaderboardCache(db, period: period) else { return nil }
        guard let data = row.payloadJson.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let resp = try? decoder.decode(LeaderboardResponse.self, from: data) else { return nil }

        func mapEntry(_ e: LeaderboardEntry) -> WidgetSnapshot.LeaderboardSlice.Entry {
            WidgetSnapshot.LeaderboardSlice.Entry(
                rank: e.rank,
                previousRank: e.previousRank,
                displayName: e.displayName,
                tokensTotal: e.tokensTotal,
                isMe: e.isMe
            )
        }

        let top8 = resp.entries.prefix(8).map(mapEntry)
        let meBelow: WidgetSnapshot.LeaderboardSlice.Entry?
        if let myCode = myFriendCode,
           !top8.contains(where: { $0.isMe }),
           let mine = resp.entries.first(where: { $0.friendCode == myCode })
        {
            meBelow = mapEntry(mine)
        } else {
            meBelow = nil
        }

        return WidgetSnapshot.LeaderboardSlice(entries: Array(top8), meBelow: meBelow)
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
