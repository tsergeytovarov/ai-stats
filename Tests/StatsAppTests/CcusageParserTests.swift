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
        XCTAssertEqual(day0.costUsd, 1.42, accuracy: 0.0001)
        XCTAssertEqual(day0.modelsJson, "[\"claude-opus-4-7\",\"claude-sonnet-4-6\"]")
        XCTAssertEqual(day0.updatedAt, "2024-05-22T10:00:00Z")
    }

    func test_empty_data_returns_empty_array() throws {
        let json = "{\"type\":\"daily\",\"data\":[],\"summary\":{}}".data(using: .utf8)!
        let rows = try CcusageParser.parse(json, source: "codex", now: { Date() })
        XCTAssertTrue(rows.isEmpty)
    }
}
