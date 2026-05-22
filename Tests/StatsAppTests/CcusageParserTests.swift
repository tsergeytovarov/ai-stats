import XCTest
@testable import StatsApp

final class CcusageParserTests: XCTestCase {
    func test_parses_fixture_into_two_rows() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-claude-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let rows = try CcusageParser.parse(data, source: "claude", now: { ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")! })
        XCTAssertEqual(rows.count, 2)

        let day0 = rows[0]
        XCTAssertEqual(day0.day, "2024-05-20")
        XCTAssertEqual(day0.source, "claude")
        XCTAssertEqual(day0.inputTokens, 17800) // 12000 + 800 + 5000
        XCTAssertEqual(day0.outputTokens, 3400)
        // opus: 10000*15 + 3000*75 + 4000*1.5 + 500*18.75 (all /1e6) = 0.390375
        // sonnet: 2000*3 + 400*15 + 1000*0.3 + 300*3.75 (all /1e6)  = 0.013425
        // total: 0.4038
        XCTAssertEqual(day0.costUsd, 0.4038, accuracy: 0.0001)
        XCTAssertEqual(day0.modelsJson, "[\"claude-opus-4-7\",\"claude-sonnet-4-6\"]")
        XCTAssertEqual(day0.updatedAt, "2024-05-22T10:00:00Z")
    }

    func test_empty_data_returns_empty_array() throws {
        let json = "{\"daily\":[],\"totals\":{}}".data(using: .utf8)!
        let rows = try CcusageParser.parse(json, source: "claude", now: { Date() })
        XCTAssertTrue(rows.isEmpty)
    }

    func test_parses_codex_fixture() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-codex-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let rows = try CcusageParser.parse(data, source: "codex", now: { ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")! })
        XCTAssertEqual(rows.count, 1)

        let day = rows[0]
        XCTAssertEqual(day.day, "2024-05-20")
        XCTAssertEqual(day.source, "codex")
        // codex inputTokens = inputTokens + cachedInputTokens = 12000 + 5000
        XCTAssertEqual(day.inputTokens, 17000)
        XCTAssertEqual(day.outputTokens, 3400)
        // gpt-5.5: 7000*10 + 2000*30 + 3000*1.25 (all /1e6) = 0.13375
        // codex-auto-review: 5000*5 + 1400*15 + 2000*0.63 (all /1e6) = 0.04726
        // total: ~0.18101
        XCTAssertEqual(day.costUsd, 0.181, accuracy: 0.0001)
        // models из объекта-словаря, отсортированные по имени
        XCTAssertEqual(day.modelsJson, "[\"codex-auto-review\",\"gpt-5.5\"]")
    }
}
