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

    // MARK: - weekStart

    func test_weekStart_wednesday_returns_sunday() {
        // 2024-05-22 is a Wednesday; its Sunday is 2024-05-19
        XCTAssertEqual(DateUtils.weekStart(forISODay: "2024-05-22"), "2024-05-19")
    }

    func test_weekStart_already_sunday_returns_same() {
        // 2024-05-19 is a Sunday
        XCTAssertEqual(DateUtils.weekStart(forISODay: "2024-05-19"), "2024-05-19")
    }

    func test_weekStart_monday_returns_previous_sunday() {
        // 2024-05-20 is a Monday; its Sunday is 2024-05-19
        XCTAssertEqual(DateUtils.weekStart(forISODay: "2024-05-20"), "2024-05-19")
    }

    func test_weekStart_saturday_returns_sunday_of_same_week() {
        // 2024-05-25 is a Saturday; its Sunday is 2024-05-19
        XCTAssertEqual(DateUtils.weekStart(forISODay: "2024-05-25"), "2024-05-19")
    }

    func test_weekStart_invalid_string_returns_nil() {
        XCTAssertNil(DateUtils.weekStart(forISODay: "not-a-date"))
    }
}
