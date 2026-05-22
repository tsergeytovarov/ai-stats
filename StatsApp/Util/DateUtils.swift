import Foundation

enum DateUtils {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
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

    static func isoDayCompact(_ date: Date) -> String {
        compactFormatter.string(from: date)
    }

    static func parseISODay(_ s: String) -> Date? {
        isoFormatter.date(from: s)
    }

    /// Возвращает `lookback + 1` ISO-дней: `[end - lookback, ..., end]`.
    /// lookback=0 → [end], lookback=6 → 7-дневная неделя оканчивающаяся `end`.
    static func daysRange(endingAt end: Date, lookback: Int) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        var days: [String] = []
        for offset in (0...max(0, lookback)).reversed() {
            guard let d = cal.date(byAdding: .day, value: -offset, to: end) else { continue }
            days.append(isoDay(d))
        }
        return days
    }
}
