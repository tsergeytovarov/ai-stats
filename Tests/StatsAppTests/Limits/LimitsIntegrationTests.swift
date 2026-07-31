import XCTest
import GRDB
@testable import StatsApp

/// Задачные тесты (LimitsCoordinatorTests, LimitsRepositoryTests,
/// DropdownAnalyticsTests) проверяли каждое звено пути «опросили → записали →
/// прочитали → показали» по отдельности. Финальное ревью ветки нашло, что
/// множества того, что пишется, и того, что читается, не совпадали (находки
/// 1, 2, 6): retry_after_at и last_attempt_at писались каждый тик, но
/// latest() и StatusItemController их не перечитывали. Этот тест гоняет весь
/// путь целиком одним прогоном — использует FakeLimitsFetcher из
/// LimitsCoordinatorTests.swift.
@MainActor
final class LimitsIntegrationTests: XCTestCase {

    private func makeDB() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)
        return queue
    }

    private func ok(_ provider: LimitProvider, pct: Double) -> ProviderLimits {
        ProviderLimits(provider: provider,
                       windows: [LimitWindow(windowMinutes: 10_080, usedPercent: pct, resetsAt: nil)],
                       status: .ok, fetchedAt: Date(timeIntervalSince1970: 0), error: nil)
    }

    // Полный путь без перезапуска: координатор опрашивает всех трёх, пишет в
    // БД, DropdownViewModel читает через LimitsRepository.latest() и обязана
    // увидеть ровно то, что было опрошено — включая производные свойства
    // (worstPercent/showsRings), которыми на самом деле пользуется UI.
    func test_full_path_tick_writes_repository_reads_viewmodel_shows() async throws {
        let dbq = try makeDB()
        let repo = LimitsRepository(db: dbq)
        let start = Date(timeIntervalSince1970: 1_000_000)

        let codex = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 42))
        let claude = FakeLimitsFetcher(provider: .claude, result: ok(.claude, pct: 10))
        let opencode = FakeLimitsFetcher(provider: .opencode, result: ok(.opencode, pct: 5))
        let coordinator = LimitsCoordinator(fetchers: [codex, claude, opencode],
                                           repository: repo, now: { start })

        await coordinator.tick()

        let syncCoordinator = SyncCoordinator(db: dbq)
        let vm = DropdownViewModel(db: dbq, syncCoordinator: syncCoordinator, limitsRepository: repo)
        await vm.loadLimits()

        XCTAssertEqual(vm.limits[.codex]?.windows.first?.usedPercent, 42)
        XCTAssertEqual(vm.limits[.claude]?.windows.first?.usedPercent, 10)
        XCTAssertEqual(vm.limits[.opencode]?.windows.first?.usedPercent, 5)
        // То же самое, чем пользуются LimitRingView/MenuBarCapsuleView для
        // заливки кольца и решения, показывать ли кольца вообще.
        XCTAssertEqual(vm.limits[.codex]?.worstPercent, 42)
        XCTAssertTrue(MenuBarCapsuleView.showsRings(for: vm.limits))
    }

    // Перезапуск приложения внутри окна троттлинга claude: retry_after_at из
    // прошлого запуска ещё в будущем — новый координатор не имеет права
    // опросить claude заново на первом же тике, но codex (независимое
    // расписание) обязан опроситься как обычно. Заодно проверяет, что попап
    // после рестарта видит именно то состояние throttled + retryAfter, что
    // персистнул прошлый запуск.
    func test_restart_restores_throttle_window_but_still_polls_unaffected_providers() async throws {
        let dbq = try makeDB()
        let repo = LimitsRepository(db: dbq)
        let start = Date(timeIntervalSince1970: 1_000_000)

        // "Прошлый запуск": claude ловит 429, codex отвечает штатно.
        let claudeBefore = FakeLimitsFetcher(
            provider: .claude,
            result: .failure(.claude, status: .throttled, error: "429",
                             retryAfter: start.addingTimeInterval(7_200)))
        let codexBefore = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 1))
        let coordinatorBefore = LimitsCoordinator(fetchers: [codexBefore, claudeBefore],
                                                  repository: repo, now: { start })
        await coordinatorBefore.tick()

        // "Перезапуск процесса": свежие инстансы фетчеров и координатора
        // поверх той же БД — ровно то, что происходит при реальном рестарте
        // Burn.app (AppContainer.init() пересоздаёт всё с нуля).
        let restart = start.addingTimeInterval(400)   // 5-минутный интервал codex истёк
        let claudeAfter = FakeLimitsFetcher(provider: .claude, result: ok(.claude, pct: 50))
        let codexAfter = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 2))
        let coordinatorAfter = LimitsCoordinator(fetchers: [codexAfter, claudeAfter],
                                                 repository: repo, now: { restart })

        await coordinatorAfter.tick()

        XCTAssertEqual(claudeAfter.calls, 0,
                       "retry_after_at ещё в будущем — claude не должен опрашиваться на первом тике")
        XCTAssertEqual(codexAfter.calls, 1,
                       "codex не привязан к троттлингу claude и обязан опроситься как обычно")

        let syncCoordinator = SyncCoordinator(db: dbq)
        let vm = DropdownViewModel(db: dbq, syncCoordinator: syncCoordinator, limitsRepository: repo)
        await vm.loadLimits()

        // Попап обязан показать состояние, персистнутое ДО рестарта, а не
        // выдумать «нет данных» просто потому что процесс перезапустился.
        XCTAssertEqual(vm.limits[.claude]?.status, .throttled)
        XCTAssertEqual(vm.limits[.claude]?.retryAfter, start.addingTimeInterval(7_200))
        XCTAssertEqual(vm.limits[.codex]?.windows.first?.usedPercent, 2)
    }
}
