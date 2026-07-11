import XCTest
@testable import StatsApp

final class AnalyticsFormatTests: XCTestCase {
    func test_tokens_formatting() {
        XCTAssertEqual(AnalyticsFormat.tokens(1_920_000_000), "1.92 млрд ток")
        XCTAssertEqual(AnalyticsFormat.tokens(1_000_000_000), "1.00 млрд ток")
        XCTAssertEqual(AnalyticsFormat.tokens(412_000_000), "412 млн ток")
        XCTAssertEqual(AnalyticsFormat.tokens(512_000), "512 тыс ток")
        XCTAssertEqual(AnalyticsFormat.tokens(1_000), "1 тыс ток")
        XCTAssertEqual(AnalyticsFormat.tokens(999), "999 ток")
        XCTAssertEqual(AnalyticsFormat.tokens(312), "312 ток")
        XCTAssertEqual(AnalyticsFormat.tokens(0), "0 ток")
    }
}
