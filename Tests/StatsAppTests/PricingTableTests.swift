import XCTest
@testable import StatsApp

final class PricingTableTests: XCTestCase {
    func test_opus_cost_matches_table() {
        // 1M input tokens by opus = $15
        let c = PricingTable.cost(model: "claude-opus-4-7", inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 15.0, accuracy: 0.0001)
    }

    func test_opus_output_75_per_M() {
        let c = PricingTable.cost(model: "claude-opus-4-7", inputTokens: 0, outputTokens: 1_000_000, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 75.0, accuracy: 0.0001)
    }

    func test_opus_cache_read_one_tenth_of_input() {
        let c = PricingTable.cost(model: "claude-opus-4-7", inputTokens: 0, outputTokens: 0, cacheReadTokens: 1_000_000, cacheCreateTokens: 0)
        XCTAssertEqual(c, 1.5, accuracy: 0.0001)
    }

    func test_unknown_model_returns_zero() {
        let c = PricingTable.cost(model: "no-such-model", inputTokens: 9_999_999, outputTokens: 9_999_999, cacheReadTokens: 0, cacheCreateTokens: 0)
        XCTAssertEqual(c, 0.0, accuracy: 0.0001)
    }
}
