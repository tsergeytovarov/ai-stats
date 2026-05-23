import XCTest
@testable import StatsApp

final class CostDeltaTests: XCTestCase {
    func test_currentGreaterThanPrevious_isUp_withPlusSign() {
        let result = DropdownFormat.formatCostDelta(current: 250.0, previous: 222.40, period: .day)
        XCTAssertEqual(result?.arrow, "▲")
        XCTAssertEqual(result?.amount, "+$27.60")
        XCTAssertEqual(result?.direction, .up)
        XCTAssertEqual(result?.labelKey, "delta.vs_yesterday")
    }

    func test_currentLessThanPrevious_isDown_withMinusSign() {
        let result = DropdownFormat.formatCostDelta(current: 200.0, previous: 250.0, period: .week)
        XCTAssertEqual(result?.arrow, "▼")
        XCTAssertEqual(result?.amount, "−$50.00")
        XCTAssertEqual(result?.direction, .down)
        XCTAssertEqual(result?.labelKey, "delta.vs_prev_week")
    }

    func test_currentZero_returnsNil() {
        let result = DropdownFormat.formatCostDelta(current: 0, previous: 30.0, period: .day)
        XCTAssertNil(result)
    }

    func test_equal_returnsNil() {
        let result = DropdownFormat.formatCostDelta(current: 30.0, previous: 30.0, period: .month)
        XCTAssertNil(result)
    }

    func test_previousZero_currentPositive_isUp() {
        let result = DropdownFormat.formatCostDelta(current: 10.0, previous: 0, period: .day)
        XCTAssertEqual(result?.arrow, "▲")
        XCTAssertEqual(result?.amount, "+$10.00")
        XCTAssertEqual(result?.direction, .up)
    }

    func test_monthPeriod_labelKey() {
        let result = DropdownFormat.formatCostDelta(current: 100.0, previous: 50.0, period: .month)
        XCTAssertEqual(result?.labelKey, "delta.vs_prev_month")
    }

    /// Разница меньше половины копейки (после округления до $0.00) скрывается,
    /// иначе пользователь увидит «▲ +$0.00» из-за float-погрешности SUM.
    func test_subCentDifference_returnsNil() {
        let result = DropdownFormat.formatCostDelta(current: 30.0, previous: 30.001, period: .day)
        XCTAssertNil(result)
    }

    /// Разница в одну копейку — выше порога, показываем.
    func test_oneCentDifference_showsDelta() {
        let result = DropdownFormat.formatCostDelta(current: 30.01, previous: 30.0, period: .day)
        XCTAssertEqual(result?.arrow, "▲")
        XCTAssertEqual(result?.direction, .up)
    }
}
