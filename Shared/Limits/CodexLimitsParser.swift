import Foundation

/// Разбор лимитов Codex из двух форматов: JSON-RPC ответа app-server (живой) и
/// строки rollout-лога (фолбэк). Чистые функции, тестируются без процессов.
enum CodexLimitsParser {

    /// Ответ `account/rateLimits/read`. Окно берём из `windowDurationMins`, а не
    /// из имени ключа: на Pro `primary` сейчас недельный, `secondary` пустой.
    static func parseRPC(_ data: Data) -> [LimitWindow] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any] else { return [] }
        return ["primary", "secondary"].compactMap { key in
            guard let part = rateLimits[key] as? [String: Any] else { return nil }
            return window(usedPercent: part["usedPercent"],
                          windowMinutes: part["windowDurationMins"],
                          resetsAt: part["resetsAt"])
        }
    }

    /// Строка rollout-лога. nil — в строке нет лимитов Codex (другой тип события,
    /// чужой limit_id или битый JSON).
    static func parseRolloutLine(_ line: String) -> [LimitWindow]? {
        guard line.contains("\"rate_limits\""),
              let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any],
              rateLimits["limit_id"] as? String == "codex" else { return nil }
        let windows = ["primary", "secondary"].compactMap { key -> LimitWindow? in
            guard let part = rateLimits[key] as? [String: Any] else { return nil }
            return window(usedPercent: part["used_percent"],
                          windowMinutes: part["window_minutes"],
                          resetsAt: part["resets_at"])
        }
        return windows.isEmpty ? nil : windows
    }

    private static func window(usedPercent: Any?, windowMinutes: Any?, resetsAt: Any?) -> LimitWindow? {
        guard let pct = (usedPercent as? NSNumber)?.doubleValue,
              let minutes = (windowMinutes as? NSNumber)?.intValue else { return nil }
        let reset = (resetsAt as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return LimitWindow(windowMinutes: minutes,
                           usedPercent: min(max(pct, 0), 100),
                           resetsAt: reset)
    }
}
