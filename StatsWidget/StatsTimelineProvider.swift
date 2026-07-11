import WidgetKit
import Foundation

struct StatsEntry: TimelineEntry {
    let date: Date
    let period: Period
    let aiCost: Double
    let aiCostPrev: Double
    let aiTokens: Int64
    let topModels: [WidgetSnapshot.ModelEntry]
    /// true — снапшота нет/не читается, показываем плейсхолдер «Открой Burn».
    let isPlaceholder: Bool
}

struct StatsTimelineProvider: AppIntentTimelineProvider {
    typealias Intent = PeriodConfigurationIntent
    typealias Entry = StatsEntry

    func placeholder(in context: Context) -> StatsEntry {
        emptyEntry(period: .day, date: Date(), isPlaceholder: false)
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
            return emptyEntry(period: period, date: Date(), isPlaceholder: true)
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
            topModels: slice.topModels,
            isPlaceholder: false
        )
    }

    private func emptyEntry(period: Period, date: Date, isPlaceholder: Bool) -> StatsEntry {
        StatsEntry(
            date: date, period: period,
            aiCost: 0, aiCostPrev: 0, aiTokens: 0, topModels: [],
            isPlaceholder: isPlaceholder
        )
    }
}
