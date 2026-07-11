import Foundation

/// Порт `parse_codex` из `scripts/analytics-prototype/experiment2.py`.
/// Ход открывается `turn_context` (model, effort). Токены — дельты кумулятивного
/// `token_count.total_token_usage` (cached_input ⊂ input). Тул-коллы — response_item
/// типов custom_tool_call / function_call / local_shell_call; правки — имя тула
/// содержит "patch". Лимиты — `rate_limits.used_percent` при `limit_id == "codex"`.
enum CodexRolloutParser {

    static func parse(
        lines: some Sequence<String>,
        sessionFallback: String = ""
    ) -> (turns: [ParsedTurn], rateLimits: [ParsedRateLimit]) {
        var turns: [ParsedTurn] = []
        var rateLimits: [ParsedRateLimit] = []

        var sessionId = ""
        var cwd = ""
        var cur: ParsedTurn?
        // Кумулятивный счётчик токенов файла: (input, cached_input, output, reasoning).
        var prevTotal: (Int64, Int64, Int64, Int64) = (0, 0, 0, 0)

        func flush(_ t: inout ParsedTurn?) {
            if let turn = t, turn.nRequests > 0 || turn.inputTokens > 0 {
                turns.append(turn)
            }
            t = nil
        }

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = d["type"] as? String
            let p = d["payload"] as? [String: Any] ?? [:]

            switch type {
            case "session_meta":
                sessionId = (p["id"] as? String) ?? sessionFallback
                cwd = (p["cwd"] as? String) ?? ""

            case "turn_context":
                flush(&cur)
                var turn = ParsedTurn(source: "codex")
                turn.ts = d["timestamp"] as? String ?? ""
                turn.session = sessionId
                turn.project = (p["cwd"] as? String) ?? cwd
                turn.model = (p["model"] as? String) ?? ""
                turn.effort = (p["effort"] as? String) ?? ""
                cur = turn

            case "response_item" where cur != nil:
                let pt = p["type"] as? String
                if pt == "message", (p["role"] as? String) == "user", cur?.promptHead.isEmpty == true {
                    let texts = (p["content"] as? [Any] ?? []).compactMap { item -> String? in
                        guard let c = item as? [String: Any],
                              let t = c["type"] as? String, t == "input_text" || t == "text"
                        else { return nil }
                        return c["text"] as? String ?? ""
                    }
                    let joined = texts.joined(separator: "\n")
                    cur?.promptHead = String(joined.prefix(300))
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "\t", with: " ")
                    cur?.promptChars = Int64(joined.count)
                } else if pt == "custom_tool_call" || pt == "function_call" || pt == "local_shell_call" {
                    cur?.nToolCalls += 1
                    if (p["name"] as? String ?? "").contains("patch") {
                        cur?.nEdits += 1
                    }
                }

            case "event_msg" where (p["type"] as? String) == "token_count":
                let ts = d["timestamp"] as? String ?? ""
                if let rl = p["rate_limits"] as? [String: Any], (rl["limit_id"] as? String) == "codex", !ts.isEmpty {
                    if let pri = usedPercent(rl["primary"]) {
                        rateLimits.append(ParsedRateLimit(ts: ts, window: "primary", usedPercent: pri))
                    }
                    if let sec = usedPercent(rl["secondary"]) {
                        rateLimits.append(ParsedRateLimit(ts: ts, window: "secondary", usedPercent: sec))
                    }
                }
                let info = p["info"] as? [String: Any] ?? [:]
                let total = info["total_token_usage"] as? [String: Any] ?? [:]
                let cum: (Int64, Int64, Int64, Int64) = (
                    int64(total["input_tokens"]) ?? 0,
                    int64(total["cached_input_tokens"]) ?? 0,
                    int64(total["output_tokens"]) ?? 0,
                    int64(total["reasoning_output_tokens"]) ?? 0
                )
                let dIn = max(0, cum.0 - prevTotal.0)
                let dCached = max(0, cum.1 - prevTotal.1)
                let dOut = max(0, cum.2 - prevTotal.2)
                prevTotal = cum
                if cur != nil && (dIn != 0 || dOut != 0) {
                    cur?.inputTokens += max(0, dIn - dCached)
                    cur?.cacheRead += dCached
                    cur?.outputTokens += dOut
                    cur?.nRequests += 1
                }

            default:
                break
            }
        }
        flush(&cur)
        return (turns, rateLimits)
    }

    private static func usedPercent(_ any: Any?) -> Double? {
        guard let dict = any as? [String: Any] else { return nil }
        if let d = dict["used_percent"] as? Double { return d }
        if let n = dict["used_percent"] as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func int64(_ any: Any?) -> Int64? {
        if let n = any as? Int64 { return n }
        if let n = any as? Int { return Int64(n) }
        if let n = any as? Double { return Int64(n) }
        if let n = any as? NSNumber { return n.int64Value }
        return nil
    }
}
