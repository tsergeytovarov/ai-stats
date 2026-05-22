import Foundation
import Combine
import SwiftUI
import GRDB

// Period enum lives in Shared/Period.swift — accessible to both app and widget targets.

extension Period {
    var titleKey: LocalizedStringKey {
        switch self {
        case .day: return "period.day"
        case .week: return "period.week"
        case .month: return "period.month"
        }
    }
}

@MainActor
final class DropdownViewModel: ObservableObject {
    private let db: any DatabaseReader
    private weak var syncCoordinator: SyncCoordinator?
    let githubEnabled: Bool

    @Published var period: Period = .day { didSet { Task { await reload() } } }
    @Published var aiTotals: AITotals = .init(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0)
    @Published var bySource: [SourceTotal] = []
    @Published var topModels: [ModelTotal] = []
    @Published var githubTotals: GitHubTotals = .init(totalCommits: 0, uniqueRepos: 0)
    @Published var loc: GitHubLOC = GitHubLOC(additions: 0, deletions: 0)
    @Published var topRepos: [RepoTotal] = []
    @Published var sparklineSeries: [Double] = []
    @Published var additionsSeries: [Double] = []
    @Published var lastSyncDescription: String = "never"

    init(db: any DatabaseReader, syncCoordinator: SyncCoordinator, githubEnabled: Bool = true) {
        self.db = db
        self.syncCoordinator = syncCoordinator
        self.githubEnabled = githubEnabled
    }

    func reload() async {
        let now = Date()
        let periodDays = DateUtils.daysRange(endingAt: now, lookback: period.lookbackDays)
        let sparkDays = DateUtils.daysRange(endingAt: now, lookback: 29)

        do {
            let snapshot = try await db.read { db -> (AITotals, [SourceTotal], [ModelTotal], GitHubTotals, GitHubLOC, [RepoTotal], [Double], [Double]) in
                let totals = try StatsQueries.aiTotals(in: db, days: periodDays)
                let bySource = try StatsQueries.aiTotalsBySource(in: db, days: periodDays)
                let models = try StatsQueries.topModels(in: db, days: periodDays, limit: 5)
                let gh = try StatsQueries.githubTotals(in: db, days: periodDays)
                let loc = try StatsQueries.githubLOC(in: db, days: periodDays)
                let repos = try StatsQueries.topRepos(in: db, days: periodDays, limit: 5)
                let costSeries = try StatsQueries.dailyAICostSeries(in: db, days: sparkDays)
                let addsSeries = try StatsQueries.dailyAdditionsSeries(in: db, days: sparkDays)
                return (totals, bySource, models, gh, loc, repos, costSeries, addsSeries)
            }
            self.aiTotals = snapshot.0
            self.bySource = snapshot.1
            self.topModels = snapshot.2
            self.githubTotals = snapshot.3
            self.loc = snapshot.4
            self.topRepos = snapshot.5
            self.sparklineSeries = snapshot.6
            self.additionsSeries = snapshot.7
            self.lastSyncDescription = relativeDescription(for: syncCoordinator?.lastSyncAt.values.max())
        } catch {
            NSLog("ai-stats reload error: \(error)")
        }
    }

    func todayCost() async -> Double {
        let today = [DateUtils.isoDayLocal(Date())]
        return (try? await db.read { db in try StatsQueries.aiTotals(in: db, days: today).totalCost }) ?? 0
    }

    func triggerSync(sources: [(name: String, fetchers: [any Fetcher])]) async {
        guard let coord = syncCoordinator else { return }
        for (name, fetchers) in sources {
            try? await coord.runOnce(source: name, fetchers: fetchers)
        }
        await reload()
    }

    private func relativeDescription(for date: Date?) -> String {
        guard let date else { return NSLocalizedString("unit.never", comment: "") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
