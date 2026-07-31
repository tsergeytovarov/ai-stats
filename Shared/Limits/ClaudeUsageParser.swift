import Foundation

/// Разбор ответа недокументированного эндпоинта `/api/oauth/usage` и вытаскивание
/// OAuth-токена из блоба Keychain, который пишет Claude Code.
enum ClaudeUsageParser {

    /// Имена окон в ответе фиксированы, поэтому раскладка по ключу здесь законна
    /// (в отличие от Codex, где длительность приезжает полем).
    private static let windowMinutes: [(key: String, minutes: Int)] = [
        ("five_hour", 300),
        ("seven_day", 10080),
    ]

    /// Живой эндпоинт отдаёт время сброса с дробными секундами
    /// (`2026-07-31T18:30:00.602320+00:00`), а дефолтный ISO8601DateFormatter
    /// такое не разбирает и молча возвращает nil. Эндпоинт недокументирован,
    /// поэтому не выбираем формат, а пробуем оба: сперва с дробной частью,
    /// потом без. Форматтеры статические — парсер зовётся на каждое окно.
    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()

    private static func parseResetTime(_ raw: String) -> Date? {
        isoWithFractionalSeconds.date(from: raw) ?? isoPlain.date(from: raw)
    }

    static func parse(_ data: Data) -> [LimitWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return windowMinutes.compactMap { entry in
            guard let raw = root[entry.key] as? [String: Any],
                  let pct = (raw["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (raw["resets_at"] as? String).flatMap(parseResetTime)
            return LimitWindow(windowMinutes: entry.minutes,
                               usedPercent: min(max(pct, 0), 100),
                               resetsAt: reset)
        }
    }

    /// Значение записи Keychain `Claude Code-credentials` — JSON, токен лежит в
    /// claudeAiOauth.accessToken.
    static func tokenFromKeychainBlob(_ blob: String) -> String? {
        guard let data = blob.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }
}
