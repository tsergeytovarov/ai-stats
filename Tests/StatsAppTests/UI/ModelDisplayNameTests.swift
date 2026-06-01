import XCTest
@testable import StatsApp

final class ModelDisplayNameTests: XCTestCase {

    // MARK: - Non-cowork sources pass through unchanged

    func test_claude_source_returns_model_unchanged() {
        XCTAssertEqual(
            DropdownFormat.modelDisplayName(model: "claude-opus-4-7", source: "claude"),
            "claude-opus-4-7"
        )
    }

    func test_codex_source_returns_model_unchanged() {
        XCTAssertEqual(
            DropdownFormat.modelDisplayName(model: "gpt-5.5", source: "codex"),
            "gpt-5.5"
        )
    }

    // MARK: - Cowork labels

    func test_cowork_opus_formats_as_cowork_label() {
        XCTAssertEqual(
            DropdownFormat.modelDisplayName(model: "claude-opus-4-7", source: "claude-cowork"),
            "Cowork (Opus 4.7)"
        )
    }

    func test_cowork_sonnet_formats_correctly() {
        XCTAssertEqual(
            DropdownFormat.modelDisplayName(model: "claude-sonnet-4-6", source: "claude-cowork"),
            "Cowork (Sonnet 4.6)"
        )
    }

    func test_cowork_haiku_formats_correctly() {
        XCTAssertEqual(
            DropdownFormat.modelDisplayName(model: "claude-haiku-4-5", source: "claude-cowork"),
            "Cowork (Haiku 4.5)"
        )
    }

    func test_cowork_haiku_with_date_suffix_strips_date() {
        // "claude-haiku-4-5-20251001" → "Cowork (Haiku 4.5)", date suffix stripped
        XCTAssertEqual(
            DropdownFormat.modelDisplayName(model: "claude-haiku-4-5-20251001", source: "claude-cowork"),
            "Cowork (Haiku 4.5)"
        )
    }

    func test_cowork_unknown_non_claude_model_uses_model_name_as_fallback() {
        // Non-Claude model in cowork session (unlikely but must not crash)
        XCTAssertEqual(
            DropdownFormat.modelDisplayName(model: "some-other-model", source: "claude-cowork"),
            "Cowork (some-other-model)"
        )
    }
}
