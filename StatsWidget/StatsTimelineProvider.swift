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
    // Поля советника (спека 2.3), глобальные — одинаковые для всех периодов.
    let advisorComputedAt: Date?
    let leakUsdPerMonth: Double?
    let topLeakTitle: String?

    /// Строка советника Large-виджета (спека 2.3). nil — строка скрыта.
    /// - расчёта не было (`advisorComputedAt == nil`) / «мало данных» (поля nil) → nil;
    /// - утечка ≤ $1.00 (сравнение в центах) → «Утечек не видно…»;
    /// - иначе → «Утекает ≈$X/мес · {topLeakTitle}» (без хвоста, если title nil).
    var advisorLine: String? {
        guard advisorComputedAt != nil, let leak = leakUsdPerMonth else { return nil }
        if Int((leak * 100).rounded()) <= 100 {
            return "Утечек не видно: модели подобраны по задачам."
        }
        var line = "Утекает ≈\(MoneyFormatter.widget(leak))/мес"
        if let topLeakTitle { line += " · \(topLeakTitle)" }
        return line
    }
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
            isPlaceholder: false,
            advisorComputedAt: snapshot.advisorComputedAt,
            leakUsdPerMonth: snapshot.leakUsdPerMonth,
            topLeakTitle: snapshot.topLeakTitle
        )
    }

    private func emptyEntry(period: Period, date: Date, isPlaceholder: Bool) -> StatsEntry {
        StatsEntry(
            date: date, period: period,
            aiCost: 0, aiCostPrev: 0, aiTokens: 0, topModels: [],
            isPlaceholder: isPlaceholder,
            advisorComputedAt: nil, leakUsdPerMonth: nil, topLeakTitle: nil
        )
    }
}
