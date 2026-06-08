import XCTest
@testable import StatsApp

final class ClaudeCoworkParserTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let sinceJan1: Date = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
    private let nowJan15: () -> Date = { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! }

    // MARK: - Empty / irrelevant entries

    func test_empty_data_returns_empty_payload() throws {
        let payload = try ClaudeCoworkParser.parse(
            files: [Data()], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertTrue(payload.dayRows.isEmpty)
        XCTAssertTrue(payload.modelRows.isEmpty)
    }

    func test_non_assistant_entries_are_ignored() throws {
        let jsonl = """
        {"type":"user","timestamp":"2026-01-15T10:00:00Z","message":{"role":"user","content":"hello"}}
        {"type":"queue-operation","timestamp":"2026-01-15T10:00:00Z"}
        """.data(using: .utf8)!

        let payload = try ClaudeCoworkParser.parse(
            files: [jsonl], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertTrue(payload.dayRows.isEmpty)
    }

    // MARK: - Single entry

    func test_single_entry_produces_correct_tokens_and_cost() throws {
        let line = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-15T10:00:00Z",
            inputTokens: 100, cacheCreate: 200, cacheRead: 300, outputTokens: 50
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [line], since: sinceJan1, timezone: utc, now: nowJan15
        )

        XCTAssertEqual(payload.dayRows.count, 1)
        let row = payload.dayRows[0]
        XCTAssertEqual(row.day, "2026-01-15")
        XCTAssertEqual(row.source, "claude-cowork")
        XCTAssertEqual(row.inputTokens, 600)        // 100 + 200 + 300
        XCTAssertEqual(row.inputTokensNoCache, 100)
        XCTAssertEqual(row.outputTokens, 50)
        XCTAssertEqual(row.modelsJson, "[\"claude-opus-4-7\"]")
        XCTAssertEqual(row.updatedAt, "2026-01-15T12:00:00Z")

        // cost = PricingTable(opus-4-7) @ $5/$25/$0.50/$6.25:
        //   input=100*5 + out=50*25 + cr=300*0.5 + cc=200*6.25 (all /1_000_000)
        //   = 500 + 1250 + 150 + 1250 = 3150 → 0.00315
        XCTAssertEqual(row.costUsd, 0.00315, accuracy: 1e-8)

        XCTAssertEqual(payload.modelRows.count, 1)
        let mr = payload.modelRows[0]
        XCTAssertEqual(mr.day, "2026-01-15")
        XCTAssertEqual(mr.source, "claude-cowork")
        XCTAssertEqual(mr.model, "claude-opus-4-7")
        XCTAssertEqual(mr.inputTokens, 600)
        XCTAssertEqual(mr.inputTokensNoCache, 100)
        XCTAssertEqual(mr.outputTokens, 50)
        XCTAssertEqual(mr.costUsd, 0.00315, accuracy: 1e-8)
    }

    // MARK: - Cache-create TTL (1h дороже 5m)

    func test_cache_create_1h_and_5m_priced_separately() throws {
        // cache_creation: 600k под 1h TTL ($10/M) + 400k под 5m ($6.25/M) на opus-4-8
        let line = assistantLine(
            id: "msg_001", model: "claude-opus-4-8",
            timestamp: "2026-01-15T10:00:00Z",
            inputTokens: 0, cacheCreate: 1_000_000, cacheRead: 0, outputTokens: 0,
            cacheCreate1h: 600_000
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [line], since: sinceJan1, timezone: utc, now: nowJan15
        )

        XCTAssertEqual(payload.modelRows.count, 1)
        // 600_000*10 + 400_000*6.25 = 6_000_000 + 2_500_000 = 8_500_000 → /1e6 = 8.5
        // (раньше всё шло по 5m-ставке: 1_000_000*6.25 = 6.25)
        XCTAssertEqual(payload.modelRows[0].costUsd, 8.5, accuracy: 1e-6)
    }

    // MARK: - Timestamp formats

    func test_timestamp_with_fractional_seconds_is_parsed() throws {
        // Реальные cowork timestamps приходят с миллисекундами: "...T10:00:00.794Z".
        // ISO8601DateFormatter с [.withInternetDateTime] их не парсит → запись терялась.
        let line = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-15T10:00:00.794Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [line], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].day, "2026-01-15")
        XCTAssertEqual(payload.dayRows[0].inputTokens, 100)
    }

    // MARK: - Synthetic model filtering

    func test_synthetic_model_entries_are_ignored() throws {
        // Claude Code пишет model="<synthetic>" для служебных сообщений
        // (compaction и т.п.). Они не должны попадать в статистику.
        let synthetic = assistantLine(
            id: "msg_001", model: "<synthetic>",
            timestamp: "2026-01-15T10:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [synthetic], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertTrue(payload.dayRows.isEmpty)
        XCTAssertTrue(payload.modelRows.isEmpty)
    }

    func test_synthetic_filtered_but_real_model_kept_same_day() throws {
        let synthetic = assistantLine(
            id: "msg_001", model: "<synthetic>",
            timestamp: "2026-01-15T08:00:00Z",
            inputTokens: 999, cacheCreate: 0, cacheRead: 0, outputTokens: 999
        )
        let real = assistantLine(
            id: "msg_002", model: "claude-opus-4-7",
            timestamp: "2026-01-15T09:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [combined(synthetic, real)], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].inputTokens, 100)   // synthetic 999 не попал
        XCTAssertEqual(payload.dayRows[0].modelsJson, "[\"claude-opus-4-7\"]")
        XCTAssertEqual(payload.modelRows.count, 1)
        XCTAssertEqual(payload.modelRows[0].model, "claude-opus-4-7")
    }

    // MARK: - Deduplication

    func test_duplicate_message_id_is_counted_once() throws {
        let line = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-15T10:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )
        // Same line twice (as cowork does in real sessions)
        let jsonl = combined(line, line)

        let payload = try ClaudeCoworkParser.parse(
            files: [jsonl], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].inputTokens, 100) // not 200
        XCTAssertEqual(payload.dayRows[0].outputTokens, 50)
    }

    func test_same_message_id_across_two_files_counted_once() throws {
        let line = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-15T10:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [line, line], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].inputTokens, 100)
    }

    // MARK: - Aggregation

    func test_two_entries_same_day_same_model_are_summed() throws {
        let line1 = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-15T08:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )
        let line2 = assistantLine(
            id: "msg_002", model: "claude-opus-4-7",
            timestamp: "2026-01-15T20:00:00Z",
            inputTokens: 200, cacheCreate: 0, cacheRead: 0, outputTokens: 100
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [combined(line1, line2)], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].inputTokens, 300)
        XCTAssertEqual(payload.dayRows[0].outputTokens, 150)
        XCTAssertEqual(payload.modelRows.count, 1)
        XCTAssertEqual(payload.modelRows[0].inputTokens, 300)
    }

    func test_two_models_same_day_produce_two_model_rows_and_one_day_row() throws {
        let line1 = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-15T08:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )
        let line2 = assistantLine(
            id: "msg_002", model: "claude-sonnet-4-6",
            timestamp: "2026-01-15T09:00:00Z",
            inputTokens: 200, cacheCreate: 0, cacheRead: 0, outputTokens: 80
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [combined(line1, line2)], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.modelRows.count, 2)
        XCTAssert(payload.modelRows.contains { $0.model == "claude-opus-4-7" })
        XCTAssert(payload.modelRows.contains { $0.model == "claude-sonnet-4-6" })
        XCTAssertEqual(payload.dayRows[0].modelsJson, "[\"claude-opus-4-7\",\"claude-sonnet-4-6\"]")
    }

    func test_multiple_files_merged_into_single_result() throws {
        let line1 = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-15T10:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )
        let line2 = assistantLine(
            id: "msg_002", model: "claude-opus-4-7",
            timestamp: "2026-01-15T11:00:00Z",
            inputTokens: 200, cacheCreate: 0, cacheRead: 0, outputTokens: 80
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [line1, line2], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].inputTokens, 300)
    }

    // MARK: - Date filtering

    func test_entry_before_since_day_is_excluded() throws {
        let line = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2025-12-31T23:59:59Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [line], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertTrue(payload.dayRows.isEmpty)
    }

    func test_entry_on_since_day_is_included() throws {
        let line = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-01T00:00:01Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [line], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].day, "2026-01-01")
    }

    func test_two_entries_on_different_days_produce_two_day_rows() throws {
        let line1 = assistantLine(
            id: "msg_001", model: "claude-opus-4-7",
            timestamp: "2026-01-14T10:00:00Z",
            inputTokens: 100, cacheCreate: 0, cacheRead: 0, outputTokens: 50
        )
        let line2 = assistantLine(
            id: "msg_002", model: "claude-opus-4-7",
            timestamp: "2026-01-15T10:00:00Z",
            inputTokens: 200, cacheCreate: 0, cacheRead: 0, outputTokens: 80
        )

        let payload = try ClaudeCoworkParser.parse(
            files: [combined(line1, line2)], since: sinceJan1, timezone: utc, now: nowJan15
        )
        XCTAssertEqual(payload.dayRows.count, 2)
        let days = Set(payload.dayRows.map { $0.day })
        XCTAssertEqual(days, ["2026-01-14", "2026-01-15"])
    }

    // MARK: - Helpers

    private func assistantLine(id: String, model: String, timestamp: String,
                                inputTokens: Int, cacheCreate: Int,
                                cacheRead: Int, outputTokens: Int,
                                cacheCreate1h: Int? = nil) -> Data {
        // Когда задан cacheCreate1h — добавляем вложенный cache_creation с разбивкой
        // 1h/5m TTL (так Claude Code пишет реальные логи). Остаток до cacheCreate — 5m.
        let cacheCreationBlock: String
        if let oneHour = cacheCreate1h {
            let fiveMin = max(0, cacheCreate - oneHour)
            cacheCreationBlock = ",\"cache_creation\":{\"ephemeral_1h_input_tokens\":\(oneHour),\"ephemeral_5m_input_tokens\":\(fiveMin)}"
        } else {
            cacheCreationBlock = ""
        }
        let json = """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"req_\(id)","message":{"id":"\(id)","model":"\(model)","role":"assistant","usage":{"input_tokens":\(inputTokens),"cache_creation_input_tokens":\(cacheCreate),"cache_read_input_tokens":\(cacheRead),"output_tokens":\(outputTokens)\(cacheCreationBlock)}}}
        """
        return json.data(using: .utf8)!
    }

    private func combined(_ parts: Data...) -> Data {
        parts
            .map { String(data: $0, encoding: .utf8)! }
            .joined(separator: "\n")
            .data(using: .utf8)!
    }
}
