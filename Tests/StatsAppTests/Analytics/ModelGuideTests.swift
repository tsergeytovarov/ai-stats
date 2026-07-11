import XCTest
@testable import StatsApp

final class ModelGuideTests: XCTestCase {

    private var fixtureURL: URL {
        Bundle(for: type(of: self)).url(forResource: "models_cache", withExtension: "json")!
    }

    func test_codex_filters_visibility_and_keeps_file_order() {
        let guide = ModelGuide.load(codexCacheURL: fixtureURL)
        XCTAssertEqual(guide.codex, [
            ModelGuide.Entry(slug: "gpt-5.6-sol", description: "Latest frontier agentic coding model."),
            ModelGuide.Entry(slug: "gpt-5.6-terra", description: "Balanced agentic coding model for everyday work."),
            ModelGuide.Entry(slug: "gpt-5.4-mini", description: "Small, fast, and cost-efficient model for simpler tasks."),
        ])
        // codex-auto-review (visibility=hide) отфильтрован
        XCTAssertFalse(guide.codex.contains { $0.slug == "codex-auto-review" })
    }

    func test_claude_static_table() {
        let guide = ModelGuide.load(codexCacheURL: fixtureURL)
        XCTAssertEqual(guide.claude.map(\.slug), ["haiku", "sonnet", "opus", "fable"])
        XCTAssertEqual(guide.claude.first?.description, "поиск по коду, простые правки, саммари")
        XCTAssertEqual(guide.claude.last?.description, "только самые тяжёлые long-horizon задачи")
    }

    func test_missing_file_yields_empty_codex_section() {
        let missing = URL(fileURLWithPath: "/nonexistent/models_cache.json")
        let guide = ModelGuide.load(codexCacheURL: missing)
        XCTAssertTrue(guide.codex.isEmpty)
        XCTAssertEqual(guide.claude.count, 4)   // Claude-раздел статичен, не зависит от файла
    }
}
