import XCTest
@testable import StatsApp

final class StatusItemControllerTests: XCTestCase {
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
}
