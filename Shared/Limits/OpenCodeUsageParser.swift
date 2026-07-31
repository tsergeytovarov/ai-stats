import Foundation

/// Разбор страницы `/workspace/<id>/go` opencode.ai. Страница отдаётся в формате
/// React Flight — не HTML-дерево и не валидный JSON, поэтому вырезаем
/// брейс-сбалансированные блоки и читаем числа только на первом уровне: внутри
/// блока встречаются вложенные объекты с теми же именами полей.
enum OpenCodeUsageParser {

    // Все имена — в нижнем регистре: filterAuthCookie сравнивает лишь после
    // .lowercased(), чтобы совпадать с тем, что normalizeCookie уже принимает
    // "Auth=" регистронезависимо (находка 10 финального ревью — до фикса
    // "Auth=…" сохранялась, но вырезалась в ноль при каждом запросе).
    private static let authCookieNames: Set<String> = ["auth", "__host-auth"]

    private static let windows: [(key: String, minutes: Int, required: Bool)] = [
        ("rollingUsage", 300, true),
        ("weeklyUsage", 10080, true),
        ("monthlyUsage", 43200, false),
    ]

    /// Голый токен оборачиваем в `auth=`; готовый заголовок не трогаем.
    static func normalizeCookie(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.contains(";") { return trimmed }
        if trimmed.lowercased().hasPrefix("auth=") || trimmed.hasPrefix("__Host-auth=") {
            return trimmed
        }
        return "auth=\(trimmed)"
    }

    /// Оставляем только auth-куки — чужие сессии на opencode.ai не отправляем.
    static func filterAuthCookie(_ raw: String) -> String {
        raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { pair in
                guard let eq = pair.firstIndex(of: "=") else { return false }
                return authCookieNames.contains(String(pair[..<eq]).lowercased())
            }
            .joined(separator: "; ")
    }

    static func parseWorkspaceIDs(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bid\s*:\s*["']((?:wrk|wk)_[a-zA-Z0-9]+)["']"#) else { return [] }
        let ns = text as NSString
        var ids: [String] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, let range = Range(m.range(at: 1), in: text) else { return }
            let id = String(text[range])
            if !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    /// nil — обязательных окон нет, то есть вёрстка поменялась. Пустой массив
    /// не отдаём: он читался бы как «лимитов нет», а это враньё.
    static func parseLimits(_ text: String, now: Date) -> [LimitWindow]? {
        var result: [LimitWindow] = []
        for spec in windows {
            guard let block = usageBlock(in: text, key: spec.key),
                  let pct = topLevelNumber(block, field: "usagePercent"),
                  let resetIn = topLevelNumber(block, field: "resetInSec") else {
                if spec.required { return nil }
                continue
            }
            result.append(LimitWindow(windowMinutes: spec.minutes,
                                      usedPercent: min(max(pct, 0), 100),
                                      resetsAt: now.addingTimeInterval(resetIn)))
        }
        return result.isEmpty ? nil : result
    }

    /// Первый брейс-сбалансированный блок у `key:`, в котором usagePercent и
    /// resetInSec лежат прямыми полями. Вхождения вида `monthlyUsage:null`
    /// пропускаем.
    private static func usageBlock(in text: String, key: String) -> String? {
        let chars = Array(text)
        let pattern = Array("\(key):")
        var index = 0
        while index + pattern.count <= chars.count {
            guard Array(chars[index..<(index + pattern.count)]) == pattern else {
                index += 1
                continue
            }
            var cursor = index + pattern.count
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            guard cursor < chars.count, chars[cursor] == "{" else {
                index += 1
                continue
            }
            var depth = 0
            var end: Int?
            for i in cursor..<chars.count {
                if chars[i] == "{" { depth += 1 }
                else if chars[i] == "}" {
                    depth -= 1
                    if depth == 0 { end = i; break }
                }
            }
            if let end {
                let block = String(chars[cursor...end])
                if topLevelNumber(block, field: "usagePercent") != nil,
                   topLevelNumber(block, field: "resetInSec") != nil {
                    return block
                }
            }
            index += 1
        }
        return nil
    }

    /// Число у поля на глубине 1 объекта. Вложенные одноимённые игнорируем —
    /// внутри блока лежит `limit:{usagePercent:…}`, который к делу не относится.
    private static func topLevelNumber(_ block: String, field: String) -> Double? {
        let chars = Array(block)
        let needle = Array(field)
        var depth = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "{" { depth += 1; i += 1; continue }
            if ch == "}" { depth -= 1; i += 1; continue }
            guard depth == 1, i + needle.count < chars.count,
                  Array(chars[i..<(i + needle.count)]) == needle else {
                i += 1
                continue
            }
            var cursor = i + needle.count
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            guard cursor < chars.count, chars[cursor] == ":" else { i += 1; continue }
            cursor += 1
            while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            var number = ""
            if cursor < chars.count, chars[cursor] == "-" { number.append("-"); cursor += 1 }
            while cursor < chars.count, chars[cursor].isNumber || chars[cursor] == "." {
                number.append(chars[cursor])
                cursor += 1
            }
            if let value = Double(number) { return value }
            i += 1
        }
        return nil
    }
}
