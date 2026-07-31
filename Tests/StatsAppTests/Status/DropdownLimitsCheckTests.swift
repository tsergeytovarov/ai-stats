import XCTest
import GRDB
@testable import StatsApp

/// Разовая проверка cookie OpenCode из настроек шла мимо репозитория и мимо
/// вью-модели попапа: «Проверить» показывало «работает, окон: N», а попап до
/// следующего тика координатора всё ещё писал «вставь cookie в настройках»
/// (находка 12 финального ревью — запись и чтение состояния опроса не были
/// сшиты для этого пути).
@MainActor
final class DropdownLimitsCheckTests: XCTestCase {

    func test_recordManualCheck_persists_result_and_refreshes_published_limits() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        let repo = LimitsRepository(db: dbq)
        let coordinator = SyncCoordinator(db: dbq)
        let vm = DropdownViewModel(db: dbq, syncCoordinator: coordinator, limitsRepository: repo)

        let checked = ProviderLimits(
            provider: .opencode,
            windows: [LimitWindow(windowMinutes: 300, usedPercent: 12, resetsAt: nil)],
            status: .ok, fetchedAt: Date(timeIntervalSince1970: 1_000), error: nil)

        XCTAssertTrue(vm.limits.isEmpty)

        await vm.recordManualCheck(checked)

        // Вью-модель попапа обновилась сразу же — не через следующий тик
        // координатора.
        XCTAssertEqual(vm.limits[.opencode]?.windows.first?.usedPercent, 12)

        // И результат действительно лежит в БД, а не только в памяти вью-модели.
        let persisted = try await repo.latest()
        XCTAssertEqual(persisted[.opencode]?.status, .ok)
        XCTAssertEqual(persisted[.opencode]?.windows.first?.usedPercent, 12)
    }

    // throttled из разовой проверки обязан пойти через тот же saveState-путь,
    // что и координатор — иначе retryAfterAt затрётся в nil, а lastSuccessAt
    // сдвинется на "сейчас" при непустых окнах (тот же баг, что чинили в
    // LimitsRepository.record для находки 4).
    func test_recordManualCheck_routes_throttled_through_saveState() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        let repo = LimitsRepository(db: dbq)
        let coordinator = SyncCoordinator(db: dbq)
        let vm = DropdownViewModel(db: dbq, syncCoordinator: coordinator, limitsRepository: repo)

        let retryAfter = Date(timeIntervalSince1970: 5_000)
        let throttled = ProviderLimits.failure(.opencode, status: .throttled, error: "429",
                                               retryAfter: retryAfter)

        await vm.recordManualCheck(throttled)

        XCTAssertEqual(vm.limits[.opencode]?.retryAfter, retryAfter)
    }
}
