import WidgetKit
import Foundation

struct StatsEntry: TimelineEntry {
    let date: Date
    let period: Period
    let aiCost: Double
    let aiCostPrev: Double
    let aiTokens: Int64
    let commits: Int64
    let uniqueRepos: Int
    let topModels: [WidgetSnapshot.ModelEntry]
    let githubEnabled: Bool
    let leaderboard: WidgetSnapshot.LeaderboardSlice?
    let myFriendCode: String?
}

struct StatsTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = PeriodConfigurationIntent
    typealias Entry = StatsEntry

    func placeholder(in context: Context) -> StatsEntry {
        emptyEntry(period: .day, date: Date(), githubEnabled: true)
    }

    func snapshot(for configuration: PeriodConfigurationIntent, in context: Context) async -> StatsEntry {
        makeEntry(period: configuration.period.sharedPeriod)
    }

    func timeline(for configuration: PeriodConfigurationIntent, in context: Context) async -> Timeline<StatsEntry> {
        let entry = makeEntry(period: configuration.period.sharedPeriod)
        let next = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(period: Period) -> StatsEntry {
        guard let snapshot = WidgetSnapshotIO.read() else {
            return emptyEntry(period: period, date: Date(), githubEnabled: false)
        }
        let slice: WidgetSnapshot.PeriodSlice
        switch period {
        case .day: slice = snapshot.day
        case .week: slice = snapshot.week
        case .month: slice = snapshot.month
        }
        return StatsEntry(
            date: snapshot.generatedAt,
            period: period,
            aiCost: slice.aiCost,
            aiCostPrev: slice.aiCostPrev,
            aiTokens: slice.aiTokens,
            commits: slice.commits,
            uniqueRepos: slice.uniqueRepos,
            topModels: slice.topModels,
            githubEnabled: snapshot.githubEnabled,
            leaderboard: slice.leaderboard,
            myFriendCode: snapshot.myFriendCode
        )
    }

    private func emptyEntry(period: Period, date: Date, githubEnabled: Bool) -> StatsEntry {
        StatsEntry(
            date: date, period: period,
            aiCost: 0, aiCostPrev: 0, aiTokens: 0,
            commits: 0, uniqueRepos: 0, topModels: [],
            githubEnabled: githubEnabled,
            leaderboard: nil,
            myFriendCode: nil
        )
    }
}
