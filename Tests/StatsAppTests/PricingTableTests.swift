import XCTest
@testable import StatsApp

final class PricingTableTests: XCTestCase {
    // MARK: - Opus 4.7 (актуальный прайс Anthropic: $5 in / $25 out / $0.50 cache-read)

    func test_opus47_input_5_per_M() {
        // 1M input-токенов Opus = $5 (раньше тут было $15 — старый прайс эпохи Opus 4/4.1)
        let c = PricingTable.cost(model: "claude-opus-4-7", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 5.0, accuracy: 0.0001)
    }

    func test_opus47_output_25_per_M() {
        let c = PricingTable.cost(model: "claude-opus-4-7", inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 25.0, accuracy: 0.0001)
    }

    func test_opus47_cache_read_one_tenth_of_input() {
        let c = PricingTable.cost(model: "claude-opus-4-7", inputTokens: 0, outputTokens: 0, cacheReadTokens: 1_000_000, cacheCreateTokens: 0)
        XCTAssertEqual(c, 0.5, accuracy: 0.0001)
    }

    // MARK: - Opus 4.8 (модель отсутствовала → нулевая ставка → cowork-cost = 0)

    func test_opus48_input_5_per_M() {
        let c = PricingTable.cost(model: "claude-opus-4-8", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 5.0, accuracy: 0.0001)
    }

    func test_opus48_output_25_per_M() {
        let c = PricingTable.cost(model: "claude-opus-4-8", inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 25.0, accuracy: 0.0001)
    }

    func test_opus48_cache_read_half_per_M() {
        let c = PricingTable.cost(model: "claude-opus-4-8", inputTokens: 0, outputTokens: 0, cacheReadTokens: 1_000_000, cacheCreateTokens: 0)
        XCTAssertEqual(c, 0.5, accuracy: 0.0001)
    }

    func test_opus48_cache_create_6_25_per_M() {
        // 5-минутный cache-write = 1.25 × input = $6.25 (cacheCreate1hTokens по умолчанию 0)
        let c = PricingTable.cost(model: "claude-opus-4-8", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 1_000_000)
        XCTAssertEqual(c, 6.25, accuracy: 0.0001)
    }

    func test_opus48_cache_create_1h_10_per_M() {
        // 1-часовой cache-write = 2 × input = $10; вся create помечена как 1h
        let c = PricingTable.cost(model: "claude-opus-4-8", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 1_000_000, cacheCreate1hTokens: 1_000_000)
        XCTAssertEqual(c, 10.0, accuracy: 0.0001)
    }

    func test_opus48_cache_create_mixed_ttl() {
        // 400k @1h ($10/M) + 600k @5m ($6.25/M) = 4.0 + 3.75 = 7.75
        let c = PricingTable.cost(model: "claude-opus-4-8", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 1_000_000, cacheCreate1hTokens: 400_000)
        XCTAssertEqual(c, 7.75, accuracy: 0.0001)
    }

    // MARK: - Haiku 4.5 (раньше считался по ставкам похороненного Haiku 3.5: $0.80/$4)

    func test_haiku45_input_1_per_M() {
        let c = PricingTable.cost(model: "claude-haiku-4-5", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 1.0, accuracy: 0.0001)
    }

    func test_haiku45_output_5_per_M() {
        let c = PricingTable.cost(model: "claude-haiku-4-5", inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 5.0, accuracy: 0.0001)
    }

    // MARK: - Family fallback: незнакомая, но узнаваемая Claude-модель → ставка семейства

    func test_unknown_opus_variant_uses_opus_rate() {
        // будущий claude-opus-4-9 ещё не в таблице — не зануляем, берём ставку Opus
        let c = PricingTable.cost(model: "claude-opus-4-9", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 5.0, accuracy: 0.0001)
    }

    func test_unknown_sonnet_variant_uses_sonnet_rate() {
        let c = PricingTable.cost(model: "claude-sonnet-5-0", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 3.0, accuracy: 0.0001)
    }

    func test_unknown_haiku_variant_uses_haiku_rate() {
        let c = PricingTable.cost(model: "claude-haiku-9-9", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 1.0, accuracy: 0.0001)
    }

    // MARK: - OpenAI gpt-5.x (сверено с developers.openai.com/api/docs/pricing)

    func test_gpt55_input_5_output_30() {
        let inp = PricingTable.cost(model: "gpt-5.5", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        let out = PricingTable.cost(model: "gpt-5.5", inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(inp, 5.0, accuracy: 0.0001)
        XCTAssertEqual(out, 30.0, accuracy: 0.0001)
    }

    func test_gpt54_input_2_5_output_15() {
        let inp = PricingTable.cost(model: "gpt-5.4", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        let out = PricingTable.cost(model: "gpt-5.4", inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(inp, 2.5, accuracy: 0.0001)
        XCTAssertEqual(out, 15.0, accuracy: 0.0001)
    }

    func test_gpt54_mini_input_0_75_output_4_5() {
        let inp = PricingTable.cost(model: "gpt-5.4-mini", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        let out = PricingTable.cost(model: "gpt-5.4-mini", inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(inp, 0.75, accuracy: 0.0001)
        XCTAssertEqual(out, 4.5, accuracy: 0.0001)
    }

    func test_gpt55_cached_input_is_one_tenth() {
        let c = PricingTable.cost(model: "gpt-5.5", inputTokens: 0, outputTokens: 0, cacheReadTokens: 1_000_000, cacheCreateTokens: 0)
        XCTAssertEqual(c, 0.5, accuracy: 0.0001)
    }

    // MARK: - Совсем неизвестная модель → ноль (без ложной уверенности)

    func test_unknown_model_returns_zero() {
        let c = PricingTable.cost(model: "no-such-model", inputTokens: 9_999_999, outputTokens: 9_999_999, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 0.0, accuracy: 0.0001)
    }
}
