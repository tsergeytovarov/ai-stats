import Foundation

/// Порт `parse_claude` из `scripts/analytics-prototype/experiment2.py`.
/// Ход = user-запись с реальным промптом (не tool_result / isMeta / isSidechain) плюс
/// все assistant-записи до следующего промпта. usage дедупится по `message.id`
/// (одно сообщение пишется несколькими строками — берём последнее вхождение).
/// Окном НЕ режет: приложение накладывает окно на этапе расчёта карточки.
enum ClaudeTranscriptParser {

    private static let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    static func parse(lines: some Sequence<String>, sessionFallback: String = "") -> [ParsedTurn] {
        var turns: [ParsedTurn] = []

        var cur: ParsedTurn?
        // Все usage-строки файла: message.id → (input, cache_read, cc5m, cc1h, output).
        // Перезапись = «последнее вхождение выигрывает» (дедуп).
        var seenMsgUsage: [String: (Int64, Int64, Int64, Int64, Int64)] = [:]
        // message.id, отнесённые к текущему ходу (set → каждый учитывается один раз за ход).
        var turnMsgIds: [String] = []
        var turnMsgIdSet: Set<String> = []

        func flush(_ t: inout ParsedTurn?) {
            guard var turn = t else { return }
            for mid in turnMsgIds {
                guard let u = seenMsgUsage[mid] else { continue }
                turn.nRequests += 1
                turn.inputTokens += u.0
                turn.cacheRead += u.1
                turn.cacheCreate5m += u.2
                turn.cacheCreate1h += u.3
                turn.outputTokens += u.4
            }
            if turn.nRequests > 0 && !turn.model.isEmpty {
                turns.append(turn)
            }
            t = nil
        }

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let ts = d["timestamp"] as? String ?? ""

            if let prompt = realPrompt(d) {
                flush(&cur)
                turnMsgIds = []
                turnMsgIdSet = []
                var turn = ParsedTurn(source: "claude-code")
                turn.ts = ts
                turn.session = (d["sessionId"] as? String) ?? sessionFallback
                turn.project = (d["cwd"] as? String) ?? ""
                turn.promptHead = truncateHead(prompt)
                turn.promptChars = Int64(prompt.count)
                cur = turn
                continue
            }

            guard (d["type"] as? String) == "assistant", cur != nil else { continue }
            let msg = d["message"] as? [String: Any] ?? [:]
            let usage = msg["usage"] as? [String: Any]
            let model = msg["model"] as? String ?? ""
            // "<synthetic>" — служебные сообщения Claude Code (compaction и т.п.);
            // пропускаем всю строку целиком (как прототип: continue до учёта usage/tool_use).
            if model == "<synthetic>" { continue }

            let mid = (msg["id"] as? String) ?? (d["requestId"] as? String) ?? (d["uuid"] as? String)
            if let usage, let mid {
                let cc = usage["cache_creation"] as? [String: Any] ?? [:]
                let cc5m = int64(cc["ephemeral_5m_input_tokens"])
                    ?? int64(usage["cache_creation_input_tokens"]) ?? 0
                let cc1h = int64(cc["ephemeral_1h_input_tokens"]) ?? 0
                seenMsgUsage[mid] = (
                    int64(usage["input_tokens"]) ?? 0,
                    int64(usage["cache_read_input_tokens"]) ?? 0,
                    cc5m,
                    cc1h,
                    int64(usage["output_tokens"]) ?? 0
                )
                if !turnMsgIdSet.contains(mid) {
                    turnMsgIdSet.insert(mid)
                    turnMsgIds.append(mid)
                }
            }

            let isSidechain = (d["isSidechain"] as? Bool) ?? false
            if !model.isEmpty && !isSidechain {
                cur?.model = model
            }
            if !isSidechain {
                for case let b as [String: Any] in (msg["content"] as? [Any] ?? []) {
                    if (b["type"] as? String) == "tool_use" {
                        cur?.nToolCalls += 1
                        if let name = b["name"] as? String, editTools.contains(name) {
                            cur?.nEdits += 1
                        }
                    }
                }
            }
        }
        flush(&cur)
        return turns
    }

    // MARK: - Helpers (порт is_real_prompt)

    /// Реальный промпт пользователя или nil. Пропускает tool_result / isMeta / isSidechain.
    private static func realPrompt(_ d: [String: Any]) -> String? {
        guard (d["type"] as? String) == "user" else { return nil }
        if (d["isSidechain"] as? Bool) == true { return nil }
        if (d["isMeta"] as? Bool) == true { return nil }
        let msg = d["message"] as? [String: Any] ?? [:]
        let content = msg["content"]
        if let str = content as? String { return str }
        if let list = content as? [Any] {
            for case let b as [String: Any] in list where (b["type"] as? String) == "tool_result" {
                return nil
            }
            let texts = list.compactMap { item -> String? in
                guard let b = item as? [String: Any], (b["type"] as? String) == "text" else { return nil }
                return b["text"] as? String ?? ""
            }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        return nil
    }

    private static func truncateHead(_ s: String) -> String {
        String(s.prefix(300))
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func int64(_ any: Any?) -> Int64? {
        if let n = any as? Int64 { return n }
        if let n = any as? Int { return Int64(n) }
        if let n = any as? Double { return Int64(n) }
        if let n = any as? NSNumber { return n.int64Value }
        return nil
    }
}
