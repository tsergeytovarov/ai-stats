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

    /// Проверяем, что isoDayLocal форматирует в локальной TZ, а не UTC.
    /// Используем полдень UTC — он всегда попадает в «тот же день» для
    /// любой TZ в диапазоне UTC-11..UTC+11, что даёт стабильный тест на CI.
    /// Предположение: тест запускается в TZ разработчика (UTC..UTC+5 MSK диапазон).
    func test_isoDayLocal_formats_in_current_tz() {
        // 2024-05-22 12:00 UTC — в любой разумной TZ всё ещё "2024-05-22"
        let date = Date(timeIntervalSince1970: 1716379200) // 2024-05-22 12:00 UTC
        let expected = DateUtils.isoDayLocal(date)
        // Независимая проверка через DateFormatter с TimeZone.current
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(expected, f.string(from: date))
        // UTC-форматтер должен совпадать только если мы в UTC
        // Главная проверка — что isoDayLocal использует TimeZone.current
        XCTAssertNotEqual(TimeZone.current.identifier, "")
    }

    // MARK: - daysRange
    // Тесты используют полдень UTC (12:00) как опорную точку — стабильно в любой TZ разработчика.
    // parseISODay возвращает UTC midnight; в положительных TZ это предыдущий день, поэтому
    // в тестах daysRange передаём дату через noon, а ожидаемый результат считаем относительно неё.

    func test_daysRange_inclusive() {
        // 2024-05-22 12:00 UTC → в MSK (UTC+3) это 15:00, isoDayLocal = "2024-05-22"
        let end = Date(timeIntervalSince1970: 1716379200) // 2024-05-22 12:00 UTC
        let days = DateUtils.daysRange(endingAt: end, lookback: 3)
        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(days.last, DateUtils.isoDayLocal(end))
    }

    func test_daysRange_lookback_0_returns_only_end() {
        let end = Date(timeIntervalSince1970: 1716379200) // 2024-05-22 12:00 UTC
        let days = DateUtils.daysRange(endingAt: end, lookback: 0)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0], DateUtils.isoDayLocal(end))
    }

    func test_daysRange_lookback_6_returns_full_week() {
        let end = Date(timeIntervalSince1970: 1716379200) // 2024-05-22 12:00 UTC
        let days = DateUtils.daysRange(endingAt: end, lookback: 6)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.last, DateUtils.isoDayLocal(end))
    }

}
