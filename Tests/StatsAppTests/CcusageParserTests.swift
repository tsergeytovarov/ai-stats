import XCTest
@testable import StatsApp

final class CcusageParserTests: XCTestCase {
    func test_parses_fixture_into_two_rows() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-claude-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let payload = try CcusageParser.parse(data, source: "claude", now: { ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")! })
        let rows = payload.dayRows
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
        let payload = try CcusageParser.parse(json, source: "claude", now: { Date() })
        XCTAssertTrue(payload.dayRows.isEmpty)
        XCTAssertTrue(payload.modelRows.isEmpty)
    }

    func test_parses_codex_fixture() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-codex-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let payload = try CcusageParser.parse(data, source: "codex", now: { ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")! })
        let rows = payload.dayRows
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

    // MARK: - per-model rows

    func test_claude_breakdown_produces_per_model_rows() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-claude-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let payload = try CcusageParser.parse(data, source: "claude", now: { ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")! })

        // Fixture: 2 days × (2 and 1 models) = 3 model rows total
        XCTAssertEqual(payload.modelRows.count, 3)

        let opus = payload.modelRows.first { $0.model == "claude-opus-4-7" && $0.day == "2024-05-20" }!
        XCTAssertEqual(opus.source, "claude")
        // inputTokens = 10000 + 500(cacheCreate) + 4000(cacheRead)
        XCTAssertEqual(opus.inputTokens, 14500)
        XCTAssertEqual(opus.outputTokens, 3000)
        // opus cost: 10000*15 + 3000*75 + 4000*1.5 + 500*18.75 (all /1e6) = 0.390375
        XCTAssertEqual(opus.costUsd, 0.390375, accuracy: 0.000001)

        let sonnet = payload.modelRows.first { $0.model == "claude-sonnet-4-6" && $0.day == "2024-05-20" }!
        // sonnet cost: 2000*3 + 400*15 + 1000*0.3 + 300*3.75 (all /1e6) = 0.013425
        XCTAssertEqual(sonnet.costUsd, 0.013425, accuracy: 0.000001)
    }

    func test_codex_models_dict_produces_per_model_rows() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-codex-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let payload = try CcusageParser.parse(data, source: "codex", now: { ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")! })

        XCTAssertEqual(payload.modelRows.count, 2)

        let gpt = payload.modelRows.first { $0.model == "gpt-5.5" }!
        XCTAssertEqual(gpt.source, "codex")
        XCTAssertEqual(gpt.day, "2024-05-20")
        // inputTokens = 7000 + 3000(cached) = 10000
        XCTAssertEqual(gpt.inputTokens, 10000)
        XCTAssertEqual(gpt.outputTokens, 2000)
        // gpt-5.5: 7000*10 + 2000*30 + 3000*1.25 (all /1e6) = 0.13375
        XCTAssertEqual(gpt.costUsd, 0.13375, accuracy: 0.000001)

        let codexModel = payload.modelRows.first { $0.model == "codex-auto-review" }!
        // codex-auto-review: 5000*5 + 1400*15 + 2000*0.63 (all /1e6) = 0.04726
        XCTAssertEqual(codexModel.costUsd, 0.04726, accuracy: 0.00001)
    }
}
