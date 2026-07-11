import XCTest
@testable import StatsApp

final class ModelGuideTests: XCTestCase {

    private var fixtureURL: URL {
        Bundle(for: type(of: self)).url(forResource: "models_cache", withExtension: "json")!
    }

    func test_codex_filters_visibility_keeps_order_and_uses_curated_ru() {
        let guide = ModelGuide.load(codexCacheURL: fixtureURL)
        // Порядок и фильтр visibility — из файла; описания — курированные русские.
        XCTAssertEqual(guide.codex.map(\.slug), ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.4-mini"])
        XCTAssertEqual(guide.codex.first?.description, "самое сложное: архитектура, длинный код, глубокий ресёрч")
        XCTAssertEqual(guide.codex.last?.description, "простые задачи, где важнее скорость и цена")
        // Английский blurb из кэша не протекает
        XCTAssertFalse(guide.codex.contains { $0.description.contains("agentic coding model") })
        // codex-auto-review (visibility=hide) отфильтрован
        XCTAssertFalse(guide.codex.contains { $0.slug == "codex-auto-review" })
    }

    func test_curated_descriptions_cover_known_slugs_only() {
        // Известные Codex-модели имеют курированный русский текст…
        for slug in ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
                     "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex-spark"] {
            XCTAssertNotNil(ModelGuide.codexDescriptions[slug], "нет текста для \(slug)")
        }
        // …а для незнакомой — нет (loadCodex возьмёт blurb из кэша как fallback).
        XCTAssertNil(ModelGuide.codexDescriptions["gpt-9.9-unknown"])
    }

    func test_claude_static_table() {
        let guide = ModelGuide.load(codexCacheURL: fixtureURL)
        XCTAssertEqual(guide.claude.map(\.slug), ["haiku", "sonnet", "opus", "fable"])
        XCTAssertEqual(guide.claude.first?.description, "поиск по коду, простые правки, саммари")
        XCTAssertEqual(guide.claude.last?.description, "самые тяжёлые многошаговые задачи")
    }

    func test_missing_file_yields_empty_codex_section() {
        let missing = URL(fileURLWithPath: "/nonexistent/models_cache.json")
        let guide = ModelGuide.load(codexCacheURL: missing)
        XCTAssertTrue(guide.codex.isEmpty)
        XCTAssertEqual(guide.claude.count, 4)   // Claude-раздел статичен, не зависит от файла
    }
}
