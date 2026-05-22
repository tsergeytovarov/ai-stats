import Foundation

enum DateUtils {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let isoFormatterLocal: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let compactFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func isoDay(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Форматирует дату в ISO day (YYYY-MM-DD) в локальном часовом поясе пользователя.
    /// Используется для фильтрации по «сегодня» и диапазонам периодов.
    static func isoDayLocal(_ date: Date) -> String {
        isoFormatterLocal.string(from: date)
    }

    static func isoDayCompact(_ date: Date) -> String {
        compactFormatter.string(from: date)
    }

    static func parseISODay(_ s: String) -> Date? {
        isoFormatter.date(from: s)
    }

    /// Возвращает ISO-дату (YYYY-MM-DD) воскресенья недели, в которую попадает `isoDay`.
    /// GitHub использует воскресенье как первый день недели.
    static func weekStart(forISODay isoDay: String) -> String? {
        guard let date = isoFormatter.date(from: isoDay) else { return nil }
        // Snap to Sunday: GitHub returns unix timestamps for Sunday 00:00 UTC.
        // Sunday = weekday 1 in .gregorian (1=Sun, 2=Mon, ..., 7=Sat)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1 // Sunday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let sunday = cal.date(from: components) else { return nil }
        return isoFormatter.string(from: sunday)
    }

    /// Возвращает `lookback + 1` ISO-дней: `[end - lookback, ..., end]`.
    /// lookback=0 → [end], lookback=6 → 7-дневная неделя оканчивающаяся `end`.
    /// Форматирует в локальном часовом поясе, чтобы Day/Week/Month-периоды
    /// совпадали с «сегодня» с точки зрения пользователя.
    static func daysRange(endingAt end: Date, lookback: Int) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        var days: [String] = []
        for offset in (0...max(0, lookback)).reversed() {
            guard let d = cal.date(byAdding: .day, value: -offset, to: end) else { continue }
            days.append(isoDayLocal(d))
        }
        return days
    }
}
