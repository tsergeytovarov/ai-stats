import XCTest
@testable import StatsApp

final class AnalyticsParserTests: XCTestCase {

    // MARK: - Claude

    func test_claude_turn_with_tools_and_edit() {
        let lines = [
            #"{"type":"user","timestamp":"2026-07-01T10:00:00Z","sessionId":"s1","cwd":"/proj","message":{"role":"user","content":"почини баг"}}"#,
            // assistant с usage и двумя tool_use (Edit — правка, Bash — нет)
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:01Z","message":{"id":"msg_a","model":"claude-opus-4-8","usage":{"input_tokens":100,"cache_read_input_tokens":200,"cache_creation":{"ephemeral_5m_input_tokens":300,"ephemeral_1h_input_tokens":50},"output_tokens":400},"content":[{"type":"tool_use","name":"Edit"},{"type":"tool_use","name":"Bash"}]}}"#,
        ]
        let turns = ClaudeTranscriptParser.parse(lines: lines)
        XCTAssertEqual(turns.count, 1)
        let t = turns[0]
        XCTAssertEqual(t.source, "claude-code")
        XCTAssertEqual(t.session, "s1")
        XCTAssertEqual(t.project, "/proj")
        XCTAssertEqual(t.model, "claude-opus-4-8")
        XCTAssertEqual(t.nRequests, 1)
        XCTAssertEqual(t.nToolCalls, 2)
        XCTAssertEqual(t.nEdits, 1)
        XCTAssertEqual(t.inputTokens, 100)
        XCTAssertEqual(t.cacheRead, 200)
        XCTAssertEqual(t.cacheCreate5m, 300)
        XCTAssertEqual(t.cacheCreate1h, 50)
        XCTAssertEqual(t.outputTokens, 400)
        XCTAssertEqual(t.promptHead, "почини баг")
        XCTAssertEqual(t.origin, "human")
    }

    func test_claude_usage_deduped_by_message_id_last_wins() {
        let lines = [
            #"{"type":"user","timestamp":"2026-07-01T10:00:00Z","sessionId":"s1","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:01Z","message":{"id":"msg_a","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":10}}}"#,
            // то же message.id — последнее вхождение выигрывает, ход считается один раз
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:02Z","message":{"id":"msg_a","model":"claude-opus-4-8","usage":{"input_tokens":999,"output_tokens":88}}}"#,
        ]
        let turns = ClaudeTranscriptParser.parse(lines: lines)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].nRequests, 1)
        XCTAssertEqual(turns[0].inputTokens, 999)   // last wins, not 100 and not 1099
        XCTAssertEqual(turns[0].outputTokens, 88)
    }

    func test_claude_synthetic_model_is_skipped() {
        let lines = [
            #"{"type":"user","timestamp":"2026-07-01T10:00:00Z","sessionId":"s1","message":{"role":"user","content":"hi"}}"#,
            // synthetic не вносит ни токены, ни tool_use
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:01Z","message":{"id":"msg_syn","model":"<synthetic>","usage":{"input_tokens":9999,"output_tokens":9999},"content":[{"type":"tool_use","name":"Edit"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:02Z","message":{"id":"msg_a","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":10}}}"#,
        ]
        let turns = ClaudeTranscriptParser.parse(lines: lines)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].model, "claude-opus-4-8")
        XCTAssertEqual(turns[0].nRequests, 1)
        XCTAssertEqual(turns[0].nToolCalls, 0)      // synthetic tool_use не учтён
        XCTAssertEqual(turns[0].inputTokens, 100)   // synthetic 9999 не попал
    }

    func test_claude_tool_result_prompt_does_not_open_new_turn() {
        // user-запись с tool_result — это ответ инструмента, а не новый промпт.
        let lines = [
            #"{"type":"user","timestamp":"2026-07-01T10:00:00Z","sessionId":"s1","message":{"role":"user","content":"первый"}}"#,
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:01Z","message":{"id":"msg_a","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":10}}}"#,
            #"{"type":"user","timestamp":"2026-07-01T10:00:02Z","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:03Z","message":{"id":"msg_b","model":"claude-opus-4-8","usage":{"input_tokens":50,"output_tokens":5}}}"#,
        ]
        let turns = ClaudeTranscriptParser.parse(lines: lines)
        XCTAssertEqual(turns.count, 1)                 // один ход, не два
        XCTAssertEqual(turns[0].nRequests, 2)          // оба assistant отнесены к нему
        XCTAssertEqual(turns[0].inputTokens, 150)
    }

    func test_claude_origin_rule() {
        func origin(for content: String) -> String {
            let lines = [
                "{\"type\":\"user\",\"timestamp\":\"2026-07-01T10:00:00Z\",\"sessionId\":\"s\",\"message\":{\"role\":\"user\",\"content\":\(content)}}",
                #"{"type":"assistant","timestamp":"2026-07-01T10:00:01Z","message":{"id":"m","model":"claude-opus-4-8","usage":{"input_tokens":1,"output_tokens":1}}}"#,
            ]
            return ClaudeTranscriptParser.parse(lines: lines).first!.origin
        }
        XCTAssertEqual(origin(for: "\"  <command-name>foo</command-name>\""), "human")  // слэш-команда, даже с ведущими пробелами
        XCTAssertEqual(origin(for: "\"<task-notification>ping\""), "auto")               // прочий < → auto
        XCTAssertEqual(origin(for: "\"обычный вопрос\""), "human")
    }

    // MARK: - Codex

    func test_codex_turn_from_cumulative_token_deltas() {
        let lines = [
            #"{"type":"session_meta","timestamp":"2026-07-01T09:00:00Z","payload":{"id":"sess-9","cwd":"/c"}}"#,
            #"{"type":"turn_context","timestamp":"2026-07-01T09:00:01Z","payload":{"model":"gpt-5.5","effort":"high","cwd":"/c"}}"#,
            #"{"type":"response_item","timestamp":"2026-07-01T09:00:02Z","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"сделай рефакторинг"}]}}"#,
            #"{"type":"response_item","timestamp":"2026-07-01T09:00:03Z","payload":{"type":"function_call","name":"shell"}}"#,
            #"{"type":"response_item","timestamp":"2026-07-01T09:00:04Z","payload":{"type":"custom_tool_call","name":"apply_patch"}}"#,
            // первый token_count: cum input 1000 (cached 200), output 300 → delta от нуля
            #"{"type":"event_msg","timestamp":"2026-07-01T09:00:05Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":300,"reasoning_output_tokens":100}}}}"#,
            // второй token_count: cum input 1500 (cached 200), output 500
            #"{"type":"event_msg","timestamp":"2026-07-01T09:00:06Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":200,"output_tokens":500}}}}"#,
        ]
        let (turns, rl) = CodexRolloutParser.parse(lines: lines)
        XCTAssertEqual(turns.count, 1)
        let t = turns[0]
        XCTAssertEqual(t.source, "codex")
        XCTAssertEqual(t.session, "sess-9")
        XCTAssertEqual(t.model, "gpt-5.5")
        XCTAssertEqual(t.effort, "high")
        XCTAssertEqual(t.nToolCalls, 2)
        XCTAssertEqual(t.nEdits, 1)                     // apply_patch содержит "patch"
        XCTAssertEqual(t.promptHead, "сделай рефакторинг")
        // request 1: input += max(0, 1000-200)=800, cache_read += 200, output += 300
        // request 2: input += max(0, 500-0)=500, cache_read += 0, output += 200
        XCTAssertEqual(t.inputTokens, 1300)
        XCTAssertEqual(t.cacheRead, 200)
        XCTAssertEqual(t.outputTokens, 500)
        XCTAssertEqual(t.nRequests, 2)
        XCTAssertTrue(rl.isEmpty)
    }

    func test_codex_rate_limits_captured_for_codex_limit_id() {
        let lines = [
            #"{"type":"session_meta","timestamp":"2026-07-01T09:00:00Z","payload":{"id":"sess-9"}}"#,
            #"{"type":"turn_context","timestamp":"2026-07-01T09:00:01Z","payload":{"model":"gpt-5.5"}}"#,
            #"{"type":"event_msg","timestamp":"2026-07-01T09:00:05Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":12.5},"secondary":{"used_percent":40.0}},"info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}}}"#,
            // не codex — игнор
            #"{"type":"event_msg","timestamp":"2026-07-01T09:00:06Z","payload":{"type":"token_count","rate_limits":{"limit_id":"other","secondary":{"used_percent":99.0}},"info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5}}}}"#,
        ]
        let (_, rl) = CodexRolloutParser.parse(lines: lines)
        XCTAssertEqual(rl.count, 2)
        XCTAssertEqual(rl[0], ParsedRateLimit(ts: "2026-07-01T09:00:05Z", window: "primary", usedPercent: 12.5))
        XCTAssertEqual(rl[1], ParsedRateLimit(ts: "2026-07-01T09:00:05Z", window: "secondary", usedPercent: 40.0))
    }
}
