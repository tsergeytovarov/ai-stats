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

    /// Возвращает массив `lookback` ISO-дней, заканчивающихся на `end` (включительно).
    /// lookback=0 → [end], lookback=3 → [end-2, end-1, end].
    static func daysRange(endingAt end: Date, lookback: Int) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        var days: [String] = []
        for offset in stride(from: max(0, lookback - 1), through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: end) else { continue }
            days.append(isoDay(d))
        }
        return days
    }
}
