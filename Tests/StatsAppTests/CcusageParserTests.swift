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
        // costUsd берётся прямо из ccusage daily[].totalCost — не считается локально.
        XCTAssertEqual(day0.costUsd, 0.5, accuracy: 0.0001)
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
        // costUsd берётся прямо из ccusage daily[].costUSD — не считается локально.
        XCTAssertEqual(day.costUsd, 1.42, accuracy: 0.0001)
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
        // costUsd берётся из ccusage modelBreakdowns[].cost напрямую.
        XCTAssertEqual(opus.costUsd, 0.45, accuracy: 0.000001)

        let sonnet = payload.modelRows.first { $0.model == "claude-sonnet-4-6" && $0.day == "2024-05-20" }!
        XCTAssertEqual(sonnet.costUsd, 0.05, accuracy: 0.000001)
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
        // gpt-5.5: 7000*5 + 2000*30 + 3000*0.50 (all /1e6) = 0.0965
        XCTAssertEqual(gpt.costUsd, 0.0965, accuracy: 0.000001)

        let codexModel = payload.modelRows.first { $0.model == "codex-auto-review" }!
        // codex-auto-review: 5000*5 + 1400*15 + 2000*0.63 (all /1e6) = 0.04726
        XCTAssertEqual(codexModel.costUsd, 0.04726, accuracy: 0.00001)
    }

    // MARK: - opencode

    /// Фикстура снята с живого `ccusage opencode daily --json` (7 дней, glm-5.2).
    /// Схема opencode совпадает с claude'овской — парсер идёт по default-ветке,
    /// и этот тест сторожит именно совпадение: сменят формат — упадёт здесь.
    func test_parses_opencode_fixture() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-opencode-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let payload = try CcusageParser.parse(data, source: "opencode", now: { ISO8601DateFormatter().date(from: "2026-08-03T10:00:00Z")! })

        XCTAssertEqual(payload.dayRows.count, 7)

        let day0 = payload.dayRows[0]
        XCTAssertEqual(day0.day, "2026-06-30")
        XCTAssertEqual(day0.source, "opencode")
        XCTAssertEqual(day0.inputTokens, 177524)      // 119284 + 0 (create) + 58240 (read)
        XCTAssertEqual(day0.inputTokensNoCache, 119284)
        XCTAssertEqual(day0.outputTokens, 387)
        XCTAssertEqual(day0.costUsd, 0.183944, accuracy: 0.000001)
        XCTAssertEqual(day0.modelsJson, "[\"glm-5.2\"]")

        // Сумма по дням сходится с totals.totalCost из того же вывода ccusage.
        let total = payload.dayRows.reduce(0) { $0 + $1.costUsd }
        XCTAssertEqual(total, 19.02716516, accuracy: 0.000001)
    }

    func test_opencode_breakdown_produces_per_model_rows() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "ccusage-opencode-daily", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let payload = try CcusageParser.parse(data, source: "opencode", now: { ISO8601DateFormatter().date(from: "2026-08-03T10:00:00Z")! })

        XCTAssertEqual(payload.modelRows.count, 7, "по одной модели в каждом дне фикстуры")
        XCTAssertTrue(payload.modelRows.allSatisfy { $0.model == "glm-5.2" && $0.source == "opencode" })

        // glm-5.2 нет в нашем PricingTable — цена обязана прийти из ccusage,
        // иначе fallback молча обнулит расход по opencode.
        let jul11 = payload.modelRows.first { $0.day == "2026-07-11" }!
        XCTAssertEqual(jul11.costUsd, 14.27915276, accuracy: 0.000001)
        XCTAssertEqual(jul11.inputTokensNoCache, 5261673)
        XCTAssertEqual(jul11.inputTokens, 30619369)   // 5261673 + 25357696
        XCTAssertEqual(jul11.outputTokens, 72530)
    }
}
