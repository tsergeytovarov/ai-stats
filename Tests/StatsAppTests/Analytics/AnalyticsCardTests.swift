import XCTest
import GRDB
@testable import StatsApp

final class AnalyticsCardTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let fixedNow: () -> Date = { ISO8601DateFormatter().date(from: "2026-07-11T12:00:00Z")! }

    private func migratedQueue() throws -> DatabaseQueue {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        return dbq
    }

    private func builder() -> AnalyticsCardBuilder {
        AnalyticsCardBuilder(now: fixedNow, timeZone: utc)
    }

    private func insertTurn(_ db: GRDB.Database, source: String, seq: Int, promptHead: String,
                            model: String, cost: Double, exp: Double, tokens: Int64) throws {
        var row = AnalyticsTurnRow(
            id: nil, source: source, ts: "2026-07-01T10:00:\(String(format: "%02d", seq % 60))Z-\(seq)",
            day: "2026-07-01", session: "\(source)-\(seq)", project: "/p", model: model,
            origin: promptHead.hasPrefix("<") ? "auto" : "human",
            promptHead: promptHead, promptChars: Int64(promptHead.count),
            nRequests: 1, inputTokens: tokens, outputTokens: 0,
            costUsd: cost, expSavedUsd: exp
        )
        try row.insert(db)
    }

    func test_no_data_state() throws {
        let dbq = try migratedQueue()
        let card = try dbq.read { db in try builder().build(in: db) }
        XCTAssertEqual(card.state, .noData)
        XCTAssertTrue(card.sources.isEmpty)
        XCTAssertNil(card.topLeakTitle)
    }

    func test_too_few_data_state() throws {
        let dbq = try migratedQueue()
        try dbq.write { db in
            for i in 0..<10 {
                try insertTurn(db, source: "codex", seq: i, promptHead: "вопрос \(i)",
                               model: "gpt-5.5", cost: 1.0, exp: 0.1, tokens: 1000)
            }
        }
        let card = try dbq.read { db in try builder().build(in: db) }
        XCTAssertEqual(card.state, .tooFewData)
        XCTAssertTrue(card.leaks.isEmpty)
        XCTAssertNil(card.topLeakTitle)
    }

    func test_ready_sums_clusters_and_limits() throws {
        let dbq = try migratedQueue()
        try dbq.write { db in
            // 30 codex role-pipeline ходов (кластер «ты — рерайтер роль x»)
            for i in 0..<30 {
                try insertTurn(db, source: "codex", seq: i, promptHead: "ты — рерайтер роль x",
                               model: "gpt-5.5", cost: 5.0, exp: 0.5, tokens: 1000)
            }
            // 10 codex коротких (кластер не проходит порог $1)
            for i in 30..<40 {
                try insertTurn(db, source: "codex", seq: i, promptHead: "короткий вопрос",
                               model: "gpt-5.5", cost: 0.5, exp: 0.05, tokens: 1000)
            }
            // 10 claude фоновых уведомлений
            for i in 40..<50 {
                try insertTurn(db, source: "claude-code", seq: i, promptHead: "<task-notification>ping",
                               model: "claude-opus-4-8", cost: 2.0, exp: 0.2, tokens: 1000)
            }
            // rate_limits secondary: эпохи [10,40 | 5,25] → month 50
            for (j, v) in [10.0, 40.0, 5.0, 25.0].enumerated() {
                try AnalyticsRateLimitRow(path: "/r.jsonl", ts: "2026-07-01T0\(j):00:00Z",
                                          window: "secondary", usedPercent: v).insert(db)
            }
        }
        let card = try dbq.read { db in try builder().build(in: db) }

        XCTAssertEqual(card.state, .ready)
        XCTAssertEqual(card.sources.count, 2)
        XCTAssertEqual(card.sources[0].source, "codex")     // codex первым
        XCTAssertEqual(card.sources[1].source, "claude-code")

        let codex = card.sources[0]
        XCTAssertEqual(codex.tokens, 40_000)
        XCTAssertEqual(codex.costUsd, 155.0, accuracy: 1e-9)
        XCTAssertEqual(codex.expSavedUsd, 15.5, accuracy: 1e-9)
        XCTAssertEqual(codex.leakPct ?? -1, 10.0, accuracy: 1e-9)
        XCTAssertEqual(codex.monthLimitPct ?? -1, 50.0, accuracy: 1e-9)
        XCTAssertEqual(codex.avgWeekLimitPct ?? -1, 50.0 / (30.0 / 7.0), accuracy: 1e-6)

        let claude = card.sources[1]
        XCTAssertEqual(claude.leakPct ?? -1, 10.0, accuracy: 1e-9)
        XCTAssertNil(claude.avgWeekLimitPct)                 // лимит только у codex

        // Σexp = 30*0.5 + 10*0.05 + 10*0.2 = 15 + 0.5 + 2.0 = 17.5
        XCTAssertEqual(card.totalExpSavedUsd, 17.5, accuracy: 1e-9)

        // Кластеры: role codex (15.0) и background claude (2.0); short не прошёл
        XCTAssertEqual(card.leaks.count, 2)
        let top = card.leaks[0]
        XCTAssertEqual(top.source, "codex")
        XCTAssertEqual(top.key, "ты — рерайтер роль x")
        XCTAssertEqual(top.nTurns, 30)
        XCTAssertEqual(top.model, "gpt-5.5")
        XCTAssertEqual(top.expSavedUsd, 15.0, accuracy: 1e-9)
        XCTAssertEqual(top.adviceText, "Зафиксируй модель этой роли в конфиге пайплайна: gpt-5.4")
        // Заголовок «по сути», а не сырой промпт.
        XCTAssertEqual(top.title, "Регулярная роль: Рерайтер роль x")
        XCTAssertEqual(card.topLeakTitle, "Регулярная роль: Рерайтер роль x")

        let bg = card.leaks[1]
        XCTAssertEqual(bg.source, "claude-code")
        XCTAssertEqual(bg.title, "Фоновые уведомления")
        XCTAssertEqual(bg.adviceText, "Фоновые уведомления обрабатывай дешёвой моделью")

        // Топ моделей по ТОКЕНАМ (не деньгам): gpt-5.5 = 40×1000, opus = 10×1000.
        XCTAssertEqual(card.topModelsByTokens.count, 2)
        XCTAssertEqual(card.topModelsByTokens[0].model, "gpt-5.5")
        XCTAssertEqual(card.topModelsByTokens[0].tokens, 40_000)
        XCTAssertEqual(card.topModelsByTokens[1].model, "claude-opus-4-8")
        XCTAssertEqual(card.topModelsByTokens[1].tokens, 10_000)
    }

    func test_top_models_by_tokens_ranks_by_tokens_not_cost() throws {
        let dbq = try migratedQueue()
        try dbq.write { db in
            // haiku: много токенов, копеечная стоимость
            for i in 0..<5 {
                try insertTurn(db, source: "claude-code", seq: i, promptHead: "q\(i)",
                               model: "claude-haiku-4-5", cost: 0.01, exp: 0, tokens: 100_000)
            }
            // opus: мало токенов, дорого
            for i in 5..<10 {
                try insertTurn(db, source: "claude-code", seq: i, promptHead: "q\(i)",
                               model: "claude-opus-4-8", cost: 50.0, exp: 0, tokens: 1_000)
            }
        }
        let top = try dbq.read { db in
            AnalyticsCardBuilder.topModelsByTokens(
                try AnalyticsTurnRow.fetchAll(db))
        }
        // По токенам haiku (500k) > opus (5k) — хотя по деньгам наоборот.
        XCTAssertEqual(top.first?.model, "claude-haiku-4-5")
        XCTAssertEqual(top.first?.tokens, 500_000)
        XCTAssertEqual(top.last?.model, "claude-opus-4-8")
    }

    /// Регрессия: токены (SourceSummary и topModelsByTokens) считаются БЕЗ кэша —
    /// той же методологией, что и главный экран «Расходы» (input_tokens_no_cache).
    /// Раньше кэш суммировался в токены и раздувал «Топ моделей» на порядки
    /// относительно вкладки «Расходы».
    func test_tokens_exclude_cache() throws {
        let dbq = try migratedQueue()
        try dbq.write { db in
            var row = AnalyticsTurnRow(
                id: nil, source: "claude-code", ts: "2026-07-01T10:00:00Z-0",
                day: "2026-07-01", session: "claude-code-0", project: "/p",
                model: "claude-opus-4-8", origin: "human",
                promptHead: "вопрос", promptChars: 6,
                nRequests: 1, inputTokens: 1_000, outputTokens: 500,
                costUsd: 10.0, expSavedUsd: 0
            )
            row.cacheRead = 1_000_000
            row.cacheCreate5m = 200_000
            row.cacheCreate1h = 50_000
            try row.insert(db)
        }
        let rows = try dbq.read { db in try AnalyticsTurnRow.fetchAll(db) }
        let card = try dbq.read { db in try builder().build(in: db) }

        // input+output = 1500, кэш (1.25M) в сумму не входит.
        XCTAssertEqual(card.sources.first?.tokens, 1_500)
        XCTAssertEqual(AnalyticsCardBuilder.topModelsByTokens(rows).first?.tokens, 1_500)
    }

    func test_ready_but_no_leaks_when_total_saving_under_dollar() throws {
        let dbq = try migratedQueue()
        try dbq.write { db in
            for i in 0..<50 {
                try insertTurn(db, source: "codex", seq: i, promptHead: "вопрос \(i)",
                               model: "gpt-5.5", cost: 1.0, exp: 0.001, tokens: 1000)
            }
        }
        let card = try dbq.read { db in try builder().build(in: db) }
        XCTAssertEqual(card.state, .ready)
        XCTAssertTrue(card.leaks.isEmpty)                    // Σexp = 0.05 ≤ $1
        XCTAssertNil(card.topLeakTitle)
    }
}
