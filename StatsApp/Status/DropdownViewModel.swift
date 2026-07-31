import Foundation
import Combine
import SwiftUI
import GRDB
import os.log

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

enum DropdownSection: String, CaseIterable, Identifiable {
    case expenses
    case analytics

    var id: String { rawValue }
    var title: String {
        switch self {
        case .expenses: return "Расходы"
        case .analytics: return "Аналитика"
        }
    }
}

@MainActor
final class DropdownViewModel: ObservableObject {
    private let db: any DatabaseReader
    private weak var syncCoordinator: SyncCoordinator?
    private let limitsRepository: LimitsRepository?

    @Published var period: Period = .day {
        didSet {
            // reload — синхронный (БД локальная, запросы — миллисекунды).
            // Раньше был Task { await reload() } — при переключении period в
            // popover'е async-Task не успевал обновить @Published так, чтобы
            // NSPopover/SwiftUI отрисовал свежее значение в том же tick'е.
            // Crumb (берёт period напрямую) обновлялся, а HeroNumber/topModels
            // (берут aiTotals/topModels) — нет, пока popover не переоткроют.
            reloadSync()
        }
    }
    @Published var section: DropdownSection = .expenses
    @Published var aiTotals: AITotals = .init(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0)
    @Published var aiTotalsPrev: AITotals = .init(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0)
    @Published var bySource: [SourceTotal] = []
    @Published var topModels: [ModelTotal] = []
    @Published var sparklineSeries: [Double] = []
    @Published var lastSyncDescription: String = "never"

    /// Карточка «Аналитика» за фикс-окно 30 дней. nil — ещё не загружалась.
    @Published var analyticsCard: AnalyticsCard?
    /// Шпаргалка моделей (Codex live + Claude static). Композируется в UI отдельно от карточки.
    @Published var modelGuide: ModelGuide?
    /// Последнее известное состояние лимитов. Пусто — опроса ещё не было.
    @Published private(set) var limits: [LimitProvider: ProviderLimits] = [:]

    init(db: any DatabaseReader,
         syncCoordinator: SyncCoordinator,
         limitsRepository: LimitsRepository? = nil) {
        self.db = db
        self.syncCoordinator = syncCoordinator
        self.limitsRepository = limitsRepository
    }

    /// Async-обёртка над reloadSync. Сохранена для существующих call site'ов
    /// (initial app start, refresh button) — там awaiт удобно.
    func reload() async {
        reloadSync()
    }

    /// Синхронный read из БД + обновление всех @Published. Делается в одном
    /// MainActor tick'е чтобы SwiftUI гарантированно подхватил все изменения
    /// в одном цикле re-render'а. БД локальная (GRDB DatabasePool), запросы
    /// порядка миллисекунд — sync read не блокирует UI заметно.
    func reloadSync() {
        let now = Date()
        let periodDays = DateUtils.daysRange(endingAt: now, lookback: period.lookbackDays)
        let prevPeriodDays = DateUtils.previousPeriodDays(endingAt: now, lookback: period.lookbackDays)
        let sparkDays = DateUtils.daysRange(endingAt: now, lookback: 29)

        AppLogger.sync.info(
            "reloadSync period=\(self.period.rawValue, privacy: .public) days=\(periodDays.count, privacy: .public)"
        )

        do {
            let snapshot = try db.read { db -> (AITotals, AITotals, [SourceTotal], [ModelTotal], [Double]) in
                let totals = try StatsQueries.aiTotals(in: db, days: periodDays)
                let totalsPrev = try StatsQueries.aiTotals(in: db, days: prevPeriodDays)
                let bySource = try StatsQueries.aiTotalsBySource(in: db, days: periodDays)
                let models = try StatsQueries.topModels(in: db, days: periodDays, limit: 5)
                let costSeries = try StatsQueries.dailyAICostSeries(in: db, days: sparkDays)
                return (totals, totalsPrev, bySource, models, costSeries)
            }
            self.aiTotals = snapshot.0
            self.aiTotalsPrev = snapshot.1
            self.bySource = snapshot.2
            self.topModels = snapshot.3
            self.sparklineSeries = snapshot.4
            self.lastSyncDescription = relativeDescription(for: syncCoordinator?.lastSyncAt.values.max())
            AppLogger.sync.info(
                "reload done period=\(self.period.rawValue, privacy: .public) totalCost=\(snapshot.0.totalCost, privacy: .public)"
            )
        } catch {
            // GRDB errors могут содержать SQL — .private. Тип ошибки тоже не делаем .public,
            // чтобы не светить internals в Console.app.
            AppLogger.sync.error("Reload failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Загружает карточку «Аналитика» из БД (окно 30 дней) + шпаргалку моделей.
    /// Вкладка «Аналитика» без переключателя периода — окно фиксировано в builder'е.
    func loadAnalytics() async {
        do {
            let card = try await db.read { db in try AnalyticsCardBuilder().build(in: db) }
            self.analyticsCard = card
            self.modelGuide = ModelGuide.load()
        } catch {
            AppLogger.sync.error("loadAnalytics failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Читает последнее состояние лимитов из базы. Опрос делает LimitsCoordinator —
    /// вью-модель только показывает то, что уже записано.
    func loadLimits() async {
        guard let limitsRepository else { return }
        limits = (try? await limitsRepository.latest()) ?? [:]
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
