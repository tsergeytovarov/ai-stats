import XCTest
import GRDB
@testable import StatsApp

final class NeverDecreaseUpserterTests: XCTestCase {
    var dbq: DatabaseQueue!

    override func setUpWithError() throws {
        dbq = try DatabaseQueue()
        try Database.migrate(dbq)
    }

    private func makeRow(day: String = "2024-05-22", source: String = "claude",
                        input: Int64 = 100, output: Int64 = 50, cost: Double = 1.0) -> AIUsageRow {
        AIUsageRow(id: nil, day: day, source: source, modelsJson: "[\"m\"]",
                   inputTokens: input, outputTokens: output, costUsd: cost,
                   updatedAt: "2024-05-22T10:00:00Z")
    }

    func test_insert_when_no_existing_row() throws {
        try dbq.write { db in
            let new = makeRow()
            try NeverDecreaseUpserter.upsertAIUsage(new, in: db)
            let count = try AIUsageRow.fetchCount(db)
            XCTAssertEqual(count, 1)
        }
    }

    func test_update_when_new_cost_greater() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertAIUsage(makeRow(cost: 1.0), in: db)
            try NeverDecreaseUpserter.upsertAIUsage(makeRow(cost: 2.0), in: db)
            let row = try AIUsageRow.fetchOne(db)!
            XCTAssertEqual(row.costUsd, 2.0)
        }
    }

    func test_keep_old_when_new_cost_lower() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertAIUsage(makeRow(cost: 5.0), in: db)
            try NeverDecreaseUpserter.upsertAIUsage(makeRow(cost: 2.0), in: db)
            let row = try AIUsageRow.fetchOne(db)!
            XCTAssertEqual(row.costUsd, 5.0)
        }
    }

    func test_keep_old_when_new_cost_equal() throws {
        try dbq.write { db in
            var first = makeRow(cost: 5.0)
            first.updatedAt = "2024-01-01T00:00:00Z"
            try NeverDecreaseUpserter.upsertAIUsage(first, in: db)
            var second = makeRow(cost: 5.0)
            second.updatedAt = "2024-12-31T00:00:00Z"
            try NeverDecreaseUpserter.upsertAIUsage(second, in: db)
            let row = try AIUsageRow.fetchOne(db)!
            XCTAssertEqual(row.updatedAt, "2024-01-01T00:00:00Z")
        }
    }

    func test_different_sources_same_day_coexist() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertAIUsage(makeRow(source: "claude"), in: db)
            try NeverDecreaseUpserter.upsertAIUsage(makeRow(source: "codex"), in: db)
            XCTAssertEqual(try AIUsageRow.fetchCount(db), 2)
        }
    }

    func test_github_insert_and_never_decrease() throws {
        let make: (Int64) -> GitHubRow = { commits in
            GitHubRow(id: nil, day: "2024-05-22", repo: "popovs/x", commits: commits, updatedAt: "2024-05-22T10:00:00Z")
        }
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertGitHub(make(3), in: db)
            try NeverDecreaseUpserter.upsertGitHub(make(5), in: db)
            try NeverDecreaseUpserter.upsertGitHub(make(2), in: db)
            let row = try GitHubRow.fetchOne(db)!
            XCTAssertEqual(row.commits, 5)
        }
    }
}
