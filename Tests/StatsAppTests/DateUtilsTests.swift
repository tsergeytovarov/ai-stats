import XCTest
@testable import StatsApp

final class DateUtilsTests: XCTestCase {
    func test_isoDay_formats_in_utc() {
        let date = Date(timeIntervalSince1970: 1716336000) // 2024-05-22 00:00 UTC
        XCTAssertEqual(DateUtils.isoDay(date), "2024-05-22")
    }

    func test_isoDay_compact_no_dashes() {
        let date = Date(timeIntervalSince1970: 1716336000)
        XCTAssertEqual(DateUtils.isoDayCompact(date), "20240522")
    }

    func test_daysRange_inclusive() {
        let end = DateUtils.parseISODay("2024-05-22")!
        let days = DateUtils.daysRange(endingAt: end, lookback: 3)
        XCTAssertEqual(days, ["2024-05-19", "2024-05-20", "2024-05-21", "2024-05-22"])
    }

    func test_daysRange_lookback_0_returns_only_end() {
        let end = DateUtils.parseISODay("2024-05-22")!
        XCTAssertEqual(DateUtils.daysRange(endingAt: end, lookback: 0), ["2024-05-22"])
    }

    func test_daysRange_lookback_6_returns_full_week() {
        let end = DateUtils.parseISODay("2024-05-22")!
        let days = DateUtils.daysRange(endingAt: end, lookback: 6)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, "2024-05-16")
        XCTAssertEqual(days.last, "2024-05-22")
    }
}
