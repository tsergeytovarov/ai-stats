import Foundation
import GRDB
import WidgetKit
#if canImport(AppKit)
import AppKit
#endif
import os.log

/// Управляет периодической синхронизацией. Single-flight per source.
@MainActor
final class SyncCoordinator {
    private let db: any DatabaseWriter
    private let now: () -> Date
    /// Тесты прокидывают свой NotificationCenter + имя, чтобы шлать synthetic wake.
    /// В проде nil — берётся NSWorkspace.shared.notificationCenter в installWakeObserverIfNeeded().
    private let testWakeCenter: NotificationCenter?
    private let testWakeName: Notification.Name?
    private var inFlight: Set<String> = []
    private var dispatchTimer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var wakeObserverCenter: NotificationCenter?
    private var configuredSources: [(name: String, fetchers: [any Fetcher])] = []
    private var configuredInterval: TimeInterval = 0
    private(set) var lastSyncAt: [String: Date] = [:]

    /// Инъектируемый ингест аналитики. Гейт «не чаще раза в час» —
    /// через `analytics_meta.last_ingest_at`. nil — ингест не сконфигурирован.
    private let analyticsIngest: (() async throws -> Void)?
    /// Минимальный интервал между ингестами аналитики (спека 5.1: не чаще раза в час).
    private static let analyticsIngestInterval: TimeInterval = 3600

    /// Тик опроса лимитов. Опционален: в тестах синка лимиты не нужны.
    var limitsTick: (@Sendable () async -> Void)?

    init(db: any DatabaseWriter,
         testWakeCenter: NotificationCenter? = nil,
         testWakeName: Notification.Name? = nil,
         now: @escaping () -> Date = Date.init,
         analyticsIngest: (() async throws -> Void)? = nil) {
        self.db = db
        self.testWakeCenter = testWakeCenter
        self.testWakeName = testWakeName
        self.now = now
        self.analyticsIngest = analyticsIngest
    }

    deinit {
        if let wakeObserver, let wakeObserverCenter {
            wakeObserverCenter.removeObserver(wakeObserver)
        }
        dispatchTimer?.cancel()
    }

    func startTimer(interval: TimeInterval, sources: [(name: String, fetchers: [any Fetcher])]) {
        dispatchTimer?.cancel()
        configuredSources = sources
        configuredInterval = interval

        // DispatchSourceTimer на main queue вместо Timer.scheduledTimer:
        // 1. Не зависит от RunLoop modes — пока main queue жива, timer стреляет.
        // 2. Лучше переживает sleep/wake циклы macOS, чем Timer на main RunLoop
        //    (который после long sleep мог замолкать на старых билдах).
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.runAllSources() }
        }
        t.resume()
        dispatchTimer = t

        // Подписка на wake. После долгого sleep'а Mac'а штатный таймер мог
        // пропустить интервалы — нотификация триггерит немедленный sync,
        // чтобы виджет/popover не сидели на устаревших данных полчаса.
        installWakeObserverIfNeeded()
    }

    func stopTimer() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
        if let wakeObserver, let wakeObserverCenter {
            wakeObserverCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
            self.wakeObserverCenter = nil
        }
    }

    /// Вызывает `runOnce` для всех configured-источников. Используется и тиком
    /// таймера, и обработчиком wake-нотификации.
    func runAllSources() async {
        for (name, fetchers) in configuredSources {
            try? await runOnce(source: name, fetchers: fetchers)
        }
        await maybeRunAnalyticsIngest()
        // Лимиты со своим расписанием внутри координатора — тут просто дёргаем
        // тик, а он сам решает, кому пора.
        await limitsTick?()
    }

    /// Ингест аналитики с гейтом «не чаще раза в час» (спека 5.1). Метка времени —
    /// `analytics_meta.last_ingest_at`. После успешного ингеста пересчитывает и
    /// пишет снапшот виджета (поля советника, C9). Возвращает true, если ингест
    /// выполнен (иначе — скип по гейту / ингест не сконфигурирован).
    /// `force` — обойти часовой гейт (используется на старте приложения: ингест
    /// всегда прогоняет пересчёт вердиктов по хранимым полям, а смена версии
    /// расчёта иначе не подхватилась бы при перезапуске в пределах часа).
    @discardableResult
    func maybeRunAnalyticsIngest(force: Bool = false) async -> Bool {
        guard let analyticsIngest else { return false }
        let nowDate = now()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        do {
            if !force {
                let lastValue = try await db.read { db in
                    try AnalyticsMetaRow
                        .filter(AnalyticsMetaRow.Columns.key == "last_ingest_at")
                        .fetchOne(db)?.value
                }
                if let lastValue, let last = iso.date(from: lastValue),
                   nowDate.timeIntervalSince(last) < Self.analyticsIngestInterval {
                    return false  // <1ч с прошлого ингеста — скип (только для тика).
                }
            }

            try await analyticsIngest()

            try await db.write { db in
                try AnalyticsMetaRow(key: "last_ingest_at", value: iso.string(from: nowDate))
                    .insert(db, onConflict: .replace)
            }
            // Пересчёт снапшота с полями советника (C9) — виджет обновляется без
            // открытия вкладки «Аналитика».
            try? buildAndWriteWidgetSnapshot()
            WidgetCenter.shared.reloadAllTimelines()
            return true
        } catch {
            AppLogger.sync.error("analytics ingest failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func installWakeObserverIfNeeded() {
        guard wakeObserver == nil else { return }
        let center: NotificationCenter
        let name: Notification.Name
        if let testWakeCenter, let testWakeName {
            center = testWakeCenter
            name = testWakeName
        } else {
            #if canImport(AppKit)
            center = NSWorkspace.shared.notificationCenter
            name = NSWorkspace.didWakeNotification
            #else
            return
            #endif
        }
        wakeObserverCenter = center
        wakeObserver = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Запускаем sync через MainActor — наш state @MainActor-isolated.
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppLogger.sync.info("Wake notification — forcing sync for all sources")
                await self.runAllSources()
            }
        }
    }

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
                // source = "ccusage"/"github" (public). error может содержать body/stderr (private).
                AppLogger.sync.error(
                    "Sync failed [\(source, privacy: .public)]: \(error.localizedDescription, privacy: .private)"
                )
            }
        }

        try recordSyncState(source: source, error: capturedError)
        lastSyncAt[source] = now()
        try? buildAndWriteWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Считает текущие totals за Day/Week/Month + prev-cost для дельт.
    /// Чистая функция: не пишет на диск.
    internal func buildSnapshot() throws -> WidgetSnapshot {
        let nowDate = now()
        let dayDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.day.lookbackDays)
        let weekDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.week.lookbackDays)
        let monthDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.month.lookbackDays)
        let dayPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.day.lookbackDays)
        let weekPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.week.lookbackDays)
        let monthPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.month.lookbackDays)

        let (day, week, month, card): (WidgetSnapshot.PeriodSlice, WidgetSnapshot.PeriodSlice, WidgetSnapshot.PeriodSlice, AnalyticsCard) = try db.read { db in
            (
                try Self.makeSlice(in: db, days: dayDays, prevDays: dayPrev),
                try Self.makeSlice(in: db, days: weekDays, prevDays: weekPrev),
                try Self.makeSlice(in: db, days: monthDays, prevDays: monthPrev),
                try AnalyticsCardBuilder(now: now).build(in: db)
            )
        }

        // Поля советника — только для собранной карточки (.ready). В режимах
        // «нет данных»/«мало данных» остаются nil → строка Large скрыта (спека 2.3).
        let advisorComputedAt: Date?
        let leakUsdPerMonth: Double?
        let topLeakTitle: String?
        if card.state == .ready {
            advisorComputedAt = card.advisorComputedAt
            leakUsdPerMonth = card.totalExpSavedUsd
            topLeakTitle = card.topLeakTitle
        } else {
            advisorComputedAt = nil
            leakUsdPerMonth = nil
            topLeakTitle = nil
        }

        return WidgetSnapshot(
            generatedAt: nowDate,
            day: day,
            week: week,
            month: month,
            advisorComputedAt: advisorComputedAt,
            leakUsdPerMonth: leakUsdPerMonth,
            topLeakTitle: topLeakTitle
        )
    }

    /// Вычисляет snapshot и пишет его в контейнер виджета.
    private func buildAndWriteWidgetSnapshot() throws {
        let snapshot = try buildSnapshot()
        try WidgetSnapshotIO.write(snapshot)
    }

    private static func makeSlice(
        in db: GRDB.Database,
        days: [String],
        prevDays: [String]
    ) throws -> WidgetSnapshot.PeriodSlice {
        let totals = try StatsQueries.aiTotals(in: db, days: days)
        let totalsPrev = try StatsQueries.aiTotals(in: db, days: prevDays)
        let models = try StatsQueries.topModels(in: db, days: days, limit: 4)

        return WidgetSnapshot.PeriodSlice(
            aiCost: totals.totalCost,
            aiCostPrev: totalsPrev.totalCost,
            aiTokens: totals.totalInputTokens + totals.totalOutputTokens,
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
