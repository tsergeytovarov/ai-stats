import XCTest
@testable import StatsApp

final class AnalyticsVerdictTests: XCTestCase {

    // MARK: - ModelLadder classification

    func test_ladder_rungs_specific_before_general() {
        XCTAssertEqual(ModelLadder.rung(for: "gpt-5.4-mini"), .small)   // раньше gpt-5.4
        XCTAssertEqual(ModelLadder.rung(for: "gpt-5.4"), .middle)
        XCTAssertEqual(ModelLadder.rung(for: "gpt-5.5"), .frontier)
        XCTAssertEqual(ModelLadder.rung(for: "gpt-5.6-sol"), .frontier)
        XCTAssertEqual(ModelLadder.rung(for: "gpt-5.6-terra"), .middle)
        XCTAssertEqual(ModelLadder.rung(for: "gpt-5.6-luna"), .small)
        XCTAssertEqual(ModelLadder.rung(for: "gpt-5.3-codex-spark"), .small)
        XCTAssertEqual(ModelLadder.rung(for: "claude-opus-4-8"), .frontier)
        XCTAssertEqual(ModelLadder.rung(for: "claude-sonnet-4-6"), .middle)
        XCTAssertEqual(ModelLadder.rung(for: "claude-haiku-4-5"), .small)
        XCTAssertNil(ModelLadder.rung(for: "mystery-model"))
        XCTAssertTrue(ModelLadder.isT0("claude-fable-5"))
        XCTAssertFalse(ModelLadder.isT0("claude-sonnet-4-6"))
    }

    // MARK: - Verdicts (числа по формуле прототипа)

    // ВАЖНО: план в C3 описывает «opus короткий вопрос → tier2, exp_saved=cost×0.057»,
    // но это коэффициент страты tier0. Прототип (нормативен) для tier1/2 даёт
    // exp_saved = max(0, cost − cf_usd). Следуем прототипу.
    func test_opus_short_question_is_tier2_with_counterfactual_saving() {
        // opus: input 100 output 100 → cost = (100*5 + 100*25)/1e6 = 0.003
        // cf haiku: (100*1 + 100*5)/1e6 = 0.0006 → exp = 0.003 - 0.0006 = 0.0024
        let v = TurnCostCalculator.verdict(
            source: "claude-code", model: "claude-opus-4-8",
            nEdits: 0, nTools: 0,
            inputTokens: 100, outputTokens: 100,
            cacheRead: 0, cacheCreate5m: 0, cacheCreate1h: 0,
            promptChars: 50
        )
        XCTAssertEqual(v.heurTier, 2)
        XCTAssertEqual(v.cfModel, "claude-haiku-4-5")
        XCTAssertEqual(v.costUsd, 0.003, accuracy: 1e-9)
        XCTAssertEqual(v.cfUsd ?? -1, 0.0006, accuracy: 1e-9)
        XCTAssertEqual(v.expSavedUsd, 0.0024, accuracy: 1e-9)
    }

    func test_gpt55_long_agentic_is_tier0_with_judge_ratio_saving() {
        // gpt-5.5: input 1000 output 10000 → cost = (1000*5 + 10000*30)/1e6 = 0.305
        // tier0 → exp = 0.305 * 0.072 (codex judgeRatioT0)
        let v = TurnCostCalculator.verdict(
            source: "codex", model: "gpt-5.5",
            nEdits: 5, nTools: 10,
            inputTokens: 1000, outputTokens: 10_000,
            cacheRead: 0, cacheCreate5m: 0, cacheCreate1h: 0,
            promptChars: 5000
        )
        XCTAssertEqual(v.heurTier, 0)
        XCTAssertNil(v.cfModel)
        XCTAssertNil(v.cfUsd)
        XCTAssertEqual(v.costUsd, 0.305, accuracy: 1e-9)
        XCTAssertEqual(v.expSavedUsd, 0.305 * 0.072, accuracy: 1e-9)
    }

    func test_sonnet_is_not_t0_no_saving() {
        let v = TurnCostCalculator.verdict(
            source: "claude-code", model: "claude-sonnet-4-6",
            nEdits: 0, nTools: 0,
            inputTokens: 1000, outputTokens: 100,
            cacheRead: 0, cacheCreate5m: 0, cacheCreate1h: 0,
            promptChars: 10
        )
        XCTAssertNil(v.heurTier)
        XCTAssertNil(v.cfModel)
        XCTAssertNil(v.cfUsd)
        XCTAssertEqual(v.expSavedUsd, 0)
        XCTAssertGreaterThan(v.costUsd, 0)   // стоимость считается всегда
    }

    func test_codex_tier1_targets_gpt54() {
        // gpt-5.6-sol (T0, codex): nEdits0 nTools2 out2000 → tier1
        // cost = gpt55 rate (sol=gpt55): (1000*5 + 2000*30)/1e6 = 0.065
        // cf gpt-5.4: (1000*2.5 + 2000*15)/1e6 = 0.0325 → exp = 0.0325
        let v = TurnCostCalculator.verdict(
            source: "codex", model: "gpt-5.6-sol",
            nEdits: 0, nTools: 2,
            inputTokens: 1000, outputTokens: 2000,
            cacheRead: 0, cacheCreate5m: 0, cacheCreate1h: 0,
            promptChars: 100
        )
        XCTAssertEqual(v.heurTier, 1)
        XCTAssertEqual(v.cfModel, "gpt-5.4")
        XCTAssertEqual(v.costUsd, 0.065, accuracy: 1e-9)
        XCTAssertEqual(v.cfUsd ?? -1, 0.0325, accuracy: 1e-9)
        XCTAssertEqual(v.expSavedUsd, 0.0325, accuracy: 1e-9)
    }

    // MARK: - enrich

    func test_enrich_sets_day_and_origin() {
        var turn = ParsedTurn(source: "claude-code")
        turn.ts = "2026-07-01T23:30:00Z"
        turn.model = "claude-opus-4-8"
        turn.promptHead = "<command-name>deploy</command-name>"
        turn.inputTokens = 100
        turn.outputTokens = 100
        turn.promptChars = 10
        let row = TurnCostCalculator.enrich(turn, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(row.day, "2026-07-01")
        XCTAssertEqual(row.origin, "human")       // <command- → human
        XCTAssertEqual(row.heurTier, 2)
        XCTAssertNil(row.id)
    }
}
