import XCTest
import GRDB
@testable import StatsApp

final class AnalyticsModelsTests: XCTestCase {

    private func migratedQueue() throws -> DatabaseQueue {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        return dbq
    }

    func test_analytics_turn_round_trip() throws {
        let dbq = try migratedQueue()
        var row = AnalyticsTurnRow(
            id: nil,
            source: "claude-code",
            ts: "2026-07-01T10:00:00.000Z",
            day: "2026-07-01",
            session: "sess-1",
            project: "/tmp/proj",
            model: "claude-opus-4-8",
            effort: "",
            origin: "human",
            promptHead: "почини баг",
            promptChars: 10,
            nRequests: 2,
            nToolCalls: 3,
            nEdits: 1,
            inputTokens: 100,
            cacheRead: 200,
            cacheCreate5m: 300,
            cacheCreate1h: 50,
            outputTokens: 400,
            costUsd: 0.01234,
            heurTier: 0,
            cfModel: nil,
            cfUsd: nil,
            expSavedUsd: 0.000703
        )
        try dbq.write { db in try row.insert(db) }
        row.id = try dbq.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM analytics_turns")
        }

        let fetched = try dbq.read { db in try AnalyticsTurnRow.fetchOne(db) }
        XCTAssertEqual(fetched, row)
    }

    func test_analytics_turn_with_counterfactual_round_trip() throws {
        let dbq = try migratedQueue()
        var row = AnalyticsTurnRow(
            id: nil,
            source: "codex",
            ts: "2026-07-02T08:00:00Z",
            day: "2026-07-02",
            session: "sess-2",
            project: "/tmp/p2",
            model: "gpt-5.5",
            effort: "high",
            origin: "auto",
            promptHead: "<task-notification>",
            promptChars: 19,
            nToolCalls: 1,
            inputTokens: 1000,
            outputTokens: 200,
            costUsd: 0.011,
            heurTier: 1,
            cfModel: "gpt-5.4",
            cfUsd: 0.0055,
            expSavedUsd: 0.0055
        )
        try dbq.write { db in try row.insert(db) }
        row.id = try dbq.read { db in try Int64.fetchOne(db, sql: "SELECT id FROM analytics_turns") }
        let fetched = try dbq.read { db in try AnalyticsTurnRow.fetchOne(db) }
        XCTAssertEqual(fetched, row)
    }

    func test_analytics_turns_unique_constraint() throws {
        let dbq = try migratedQueue()
        try dbq.write { db in
            var a = AnalyticsTurnRow(id: nil, source: "codex", ts: "T", day: "2026-07-02",
                                     session: "s", project: "", model: "gpt-5.5", origin: "human")
            try a.insert(db)
            var b = a
            b.model = "gpt-5.4"
            XCTAssertThrowsError(try b.insert(db))
        }
    }

    func test_ingest_state_round_trip() throws {
        let dbq = try migratedQueue()
        let row = AnalyticsIngestStateRow(path: "/tmp/a.jsonl", mtime: 1_720_000_000.5, size: 4096)
        try dbq.write { db in try row.insert(db) }
        let fetched = try dbq.read { db in try AnalyticsIngestStateRow.fetchOne(db) }
        XCTAssertEqual(fetched, row)
    }

    func test_meta_round_trip() throws {
        let dbq = try migratedQueue()
        let row = AnalyticsMetaRow(key: "pricing_version", value: "3")
        try dbq.write { db in try row.insert(db) }
        let fetched = try dbq.read { db in try AnalyticsMetaRow.fetchOne(db) }
        XCTAssertEqual(fetched, row)
    }

    func test_rate_limit_round_trip() throws {
        let dbq = try migratedQueue()
        let row = AnalyticsRateLimitRow(path: "/tmp/r.jsonl", ts: "2026-07-02T08:00:00Z",
                                        window: "secondary", usedPercent: 42.5)
        try dbq.write { db in try row.insert(db) }
        let fetched = try dbq.read { db in try AnalyticsRateLimitRow.fetchOne(db) }
        XCTAssertEqual(fetched, row)
    }
}
