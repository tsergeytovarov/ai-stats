import WidgetKit
import GRDB

struct StatsEntry: TimelineEntry {
    let date: Date
    let period: Period
    let aiTotals: AITotals
    let githubTotals: GitHubTotals
    let topModels: [ModelTotal]
    let githubEnabled: Bool
}

struct StatsTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = PeriodConfigurationIntent
    typealias Entry = StatsEntry

    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(
            date: Date(),
            period: .day,
            aiTotals: AITotals(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0),
            githubTotals: GitHubTotals(totalCommits: 0, uniqueRepos: 0),
            topModels: [],
            githubEnabled: true
        )
    }

    func snapshot(for configuration: PeriodConfigurationIntent, in context: Context) async -> StatsEntry {
        await makeEntry(period: configuration.period.sharedPeriod)
    }

    func timeline(for configuration: PeriodConfigurationIntent, in context: Context) async -> Timeline<StatsEntry> {
        let entry = await makeEntry(period: configuration.period.sharedPeriod)
        // Обновлять каждые 15 минут.
        let next = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(period: Period) async -> StatsEntry {
        let now = Date()
        let days = DateUtils.daysRange(endingAt: now, lookback: period.lookbackDays)
        do {
            let pool = try Database.openPool()
            let result: (AITotals, GitHubTotals, [ModelTotal]) = try await pool.read { db in
                let totals = try StatsQueries.aiTotals(in: db, days: days)
                let gh = try StatsQueries.githubTotals(in: db, days: days)
                let models = try StatsQueries.topModels(in: db, days: days, limit: 4)
                return (totals, gh, models)
            }
            return StatsEntry(
                date: now,
                period: period,
                aiTotals: result.0,
                githubTotals: result.1,
                topModels: result.2,
                githubEnabled: result.1.totalCommits > 0 || result.1.uniqueRepos > 0
            )
        } catch {
            NSLog("ai-stats widget timeline error: \(error)")
            return StatsEntry(
                date: Date(),
                period: period,
                aiTotals: AITotals(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0),
                githubTotals: GitHubTotals(totalCommits: 0, uniqueRepos: 0),
                topModels: [],
                githubEnabled: false
            )
        }
    }
}
