import XCTest
@testable import StatsApp

final class MoneyFormatterTests: XCTestCase {
    func test_widgetMoney_roundsToInteger_noDecimals() {
        XCTAssertEqual(MoneyFormatter.widget(1602.78), "$1\u{00A0}603")
        XCTAssertEqual(MoneyFormatter.widget(389.69), "$390")
        XCTAssertEqual(MoneyFormatter.widget(9.95), "$10")
        XCTAssertEqual(MoneyFormatter.widget(0.49), "$0")
        XCTAssertEqual(MoneyFormatter.widget(0.5), "$1")
    }

    func test_widgetDelta_keepsSignAndRounds() {
        XCTAssertEqual(MoneyFormatter.widgetDelta(389.69), "+$390")
        XCTAssertEqual(MoneyFormatter.widgetDelta(-50.40), "−$50")  // U+2212
        XCTAssertEqual(MoneyFormatter.widgetDelta(0), "$0")
    }

    func test_popoverMoney_keepsCents() {
        XCTAssertEqual(MoneyFormatter.popover(1602.78), "$1\u{00A0}602.78")
        XCTAssertEqual(MoneyFormatter.popover(0.49), "$0.49")
    }
}
