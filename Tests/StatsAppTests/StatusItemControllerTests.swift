import XCTest
import GRDB
@testable import StatsApp

final class StatusItemControllerTests: XCTestCase {
    // MARK: - refreshTitle

    // refreshTitle() крутится по таймеру раз в 30 секунд, а viewModel.limits
    // раньше наполнялся только из loadLimits(), вызываемого на старте и при
    // открытии попапа — кольца в меню-баре замерзали на снимке на момент
    // запуска и оживали только когда попап уже открыт (находка 1 финального
    // ревью). refreshTitle обязан дочитывать лимиты сам.
    @MainActor
    func test_refreshTitle_reloads_limits_written_after_viewModel_was_created() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        let repo = LimitsRepository(db: dbq)
        let coordinator = SyncCoordinator(db: dbq)
        let vm = DropdownViewModel(db: dbq, syncCoordinator: coordinator, limitsRepository: repo)
        let controller = StatusItemController(viewModel: vm, onRefresh: {}, onOpenSettings: {}, onQuit: {})

        // Симулирует тик координатора, случившийся пока меню-бар уже виден,
        // но попап ещё ни разу не открывали — loadLimits() тогда не звался.
        try await repo.record(
            ProviderLimits(provider: .codex,
                          windows: [LimitWindow(windowMinutes: 10_080, usedPercent: 42, resetsAt: nil)],
                          status: .ok, fetchedAt: Date(), error: nil),
            now: Date())
        XCTAssertTrue(vm.limits.isEmpty)

        await controller.refreshTitle()

        XCTAssertEqual(vm.limits[.codex]?.windows.first?.usedPercent, 42)
    }

    // MARK: - capsuleWidth

    func test_capsuleWidth_returnsPositive_forEmptyText() {
        let w = StatusItemController.capsuleWidth(for: "")
        // Минимум — ember(12) + spacing(4) + padding(16) = 32pt без текста.
        XCTAssertGreaterThanOrEqual(w, 32)
    }

    func test_capsuleWidth_growsWithLongerText() {
        let short = StatusItemController.capsuleWidth(for: "$0.00")
        let long = StatusItemController.capsuleWidth(for: "$1234.56")
        XCTAssertGreaterThan(long, short, "ширина должна расти на более длинном тексте")
    }

    func test_capsuleWidth_isStable_forSameInput() {
        // Детерминированность: один и тот же priceText → один и тот же width.
        // Это главное свойство — раньше fittingSize возвращал разные значения
        // на каждом тике, capsule прыгал в 3 стадии.
        let a = StatusItemController.capsuleWidth(for: "$879.85")
        let b = StatusItemController.capsuleWidth(for: "$879.85")
        XCTAssertEqual(a, b)
    }

    func test_capsuleWidth_realisticValuesAreReasonable() {
        // Sanity-check: типичное "$1.23" не должно быть < 50pt и не должно быть > 200pt.
        let w = StatusItemController.capsuleWidth(for: "$1.23")
        XCTAssertGreaterThan(w, 50)
        XCTAssertLessThan(w, 200)
    }

    func test_capsuleWidth_addsExactRingsGeometry_whenShowsRingsTrue() {
        // Дельта между "с кольцами" и "без колец" обязана точно совпасть с
        // геометрией блока колец в MenuBarCapsuleView:
        //   доп. spacing(4) внешнего HStack — с кольцами у него 3 ребёнка
        //   (Ember, Text, HStack колец) вместо 2, то есть 2 промежутка вместо 1;
        //   + padding(.leading, 2) перед блоком колец;
        //   + 3 кольца по 10pt + 2 промежутка по 3pt между ними (HStack(spacing: 3)).
        // Раньше второй spacing(4) не добавлялся — правый край последнего кольца
        // уезжал под обрезку NSStatusItem. Тест ловит именно эту регрессию, а не
        // фиксирует текущее магическое число.
        let withoutRings = StatusItemController.capsuleWidth(for: "$1.23", showsRings: false)
        let withRings = StatusItemController.capsuleWidth(for: "$1.23", showsRings: true)
        let expectedDelta: CGFloat = 4 + 2 + 3 * 10 + 2 * 3
        XCTAssertEqual(withRings - withoutRings, expectedDelta)
    }
}
