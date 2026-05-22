import XCTest
import GRDB
@testable import StatsApp

final class DatabaseTests: XCTestCase {
    func test_migrate_creates_tables_and_indexes() throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try dbq.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            XCTAssertEqual(Set(tables), ["ai_usage", "github_activity", "github_loc_weekly", "grdb_migrations", "sync_state"])

            let indexes = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name")
            XCTAssertTrue(indexes.contains("idx_ai_usage_day"))
            XCTAssertTrue(indexes.contains("idx_github_day"))
            XCTAssertTrue(indexes.contains("idx_github_loc_week"))
        }
    }

    func test_unique_constraint_ai_usage_day_source() throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try dbq.write { db in
            var row = AIUsageRow(id: nil, day: "2024-05-22", source: "claude", modelsJson: "[]", inputTokens: 100, outputTokens: 50, costUsd: 1.0, updatedAt: "2024-05-22T10:00:00Z")
            try row.insert(db)
            row.inputTokens = 200
            XCTAssertThrowsError(try row.insert(db))
        }
    }
}
