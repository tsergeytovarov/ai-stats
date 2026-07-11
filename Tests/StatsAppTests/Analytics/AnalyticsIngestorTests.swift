import XCTest
import GRDB
@testable import StatsApp

final class AnalyticsIngestorTests: XCTestCase {

    private var tmp: URL!
    private var claudeBase: URL!
    private var codexBase: URL!
    private let utc = TimeZone(identifier: "UTC")!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("analytics-ingest-\(UUID().uuidString)")
        claudeBase = tmp.appendingPathComponent(".claude/projects/proj")
        codexBase = tmp.appendingPathComponent(".codex/sessions/2026")
        try FileManager.default.createDirectory(at: claudeBase, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexBase, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func migratedQueue() throws -> DatabaseQueue {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        return dbq
    }

    private func ingestor(_ dbq: DatabaseQueue, pricingVersion: String = AnalyticsIngestor.currentPricingVersion) -> AnalyticsIngestor {
        AnalyticsIngestor(
            claudeProjectsBaseURL: tmp.appendingPathComponent(".claude/projects"),
            codexSessionsBaseURL: tmp.appendingPathComponent(".codex/sessions"),
            dbWriter: dbq,
            timeZone: utc,
            now: { ISO8601DateFormatter().date(from: "2026-07-05T00:00:00Z")! },
            pricingVersion: pricingVersion
        )
    }

    private func write(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)!.write(to: url)
    }

    private let claudeTruncated = """
    {"type":"user","timestamp":"2026-07-01T10:00:00Z","sessionId":"s1","message":{"role":"user","content":"hi"}}
    {"type":"assistant","timestamp":"2026-07-01T10:00:01Z","message":{"id":"msg_a","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":10}}}
    """

    private let claudeFull = """
    {"type":"user","timestamp":"2026-07-01T10:00:00Z","sessionId":"s1","message":{"role":"user","content":"hi"}}
    {"type":"assistant","timestamp":"2026-07-01T10:00:01Z","message":{"id":"msg_a","model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":10}}}
    {"type":"assistant","timestamp":"2026-07-01T10:00:02Z","message":{"id":"msg_b","model":"claude-opus-4-8","usage":{"input_tokens":50,"output_tokens":5}}}
    """

    private let codexFile = """
    {"type":"session_meta","timestamp":"2026-07-01T09:00:00Z","payload":{"id":"csess","cwd":"/c"}}
    {"type":"turn_context","timestamp":"2026-07-01T09:00:01Z","payload":{"model":"gpt-5.5","effort":"high"}}
    {"type":"event_msg","timestamp":"2026-07-01T09:00:05Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","secondary":{"used_percent":40.0}},"info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":300}}}}
    """

    func test_double_ingest_no_dupes() async throws {
        let dbq = try migratedQueue()
        try write(claudeTruncated, to: claudeBase.appendingPathComponent("a.jsonl"))
        try write(codexFile, to: codexBase.appendingPathComponent("c.jsonl"))

        try await ingestor(dbq).ingest()
        try await ingestor(dbq).ingest()

        let counts = try await dbq.read { db -> (Int, Int) in
            (try AnalyticsTurnRow.fetchCount(db), try AnalyticsRateLimitRow.fetchCount(db))
        }
        XCTAssertEqual(counts.0, 2)   // 1 claude + 1 codex turn
        XCTAssertEqual(counts.1, 1)   // 1 secondary rate-limit наблюдение
    }

    func test_changed_file_amends_truncated_turn() async throws {
        let dbq = try migratedQueue()
        let file = claudeBase.appendingPathComponent("a.jsonl")
        try write(claudeTruncated, to: file)
        try await ingestor(dbq).ingest()

        let before = try await dbq.read { db in try AnalyticsTurnRow.fetchOne(db)! }
        XCTAssertEqual(before.nRequests, 1)
        XCTAssertEqual(before.inputTokens, 100)

        // Файл дописан (size изменился → гейт перечитает), тот же session/ts.
        try write(claudeFull, to: file)
        try await ingestor(dbq).ingest()

        let rows = try await dbq.read { db in try AnalyticsTurnRow.fetchAll(db) }
        XCTAssertEqual(rows.count, 1)               // не задвоился
        XCTAssertEqual(rows[0].nRequests, 2)        // дополнен
        XCTAssertEqual(rows[0].inputTokens, 150)
    }

    func test_pricing_version_bump_recomputes_in_place() async throws {
        let dbq = try migratedQueue()
        try write(codexFile, to: codexBase.appendingPathComponent("c.jsonl"))
        try await ingestor(dbq, pricingVersion: "1").ingest()

        let correctCost = try await dbq.read { db in try AnalyticsTurnRow.fetchOne(db)!.costUsd }
        XCTAssertGreaterThan(correctCost, 0)

        // Портим стоимость в БД.
        try await dbq.write { db in try db.execute(sql: "UPDATE analytics_turns SET cost_usd = 999.0") }

        // Реингест на той же версии: файл не менялся, версия та же → пересчёта нет.
        try await ingestor(dbq, pricingVersion: "1").ingest()
        let stillCorrupt = try await dbq.read { db in try AnalyticsTurnRow.fetchOne(db)!.costUsd }
        XCTAssertEqual(stillCorrupt, 999.0, accuracy: 1e-9)

        // Бамп версии → пересчёт in-place по хранимым полям.
        try await ingestor(dbq, pricingVersion: "2").ingest()
        let recomputed = try await dbq.read { db in try AnalyticsTurnRow.fetchOne(db)!.costUsd }
        XCTAssertEqual(recomputed, correctCost, accuracy: 1e-9)
    }
}
