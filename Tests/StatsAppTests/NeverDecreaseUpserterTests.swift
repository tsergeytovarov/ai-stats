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

    // MARK: - LOC

    private func makeLOCRow(weekStart: String = "2024-05-19", repo: String = "popovs/x",
                             additions: Int64 = 100, deletions: Int64 = 50) -> GitHubLOCWeeklyRow {
        GitHubLOCWeeklyRow(id: nil, weekStart: weekStart, repo: repo,
                           additions: additions, deletions: deletions,
                           updatedAt: "2024-05-22T10:00:00Z")
    }

    func test_loc_insert_when_no_existing_row() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(), in: db)
            XCTAssertEqual(try GitHubLOCWeeklyRow.fetchCount(db), 1)
        }
    }

    func test_loc_update_when_new_total_greater() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(additions: 100, deletions: 50), in: db)
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(additions: 200, deletions: 80), in: db)
            let row = try GitHubLOCWeeklyRow.fetchOne(db)!
            XCTAssertEqual(row.additions, 200)
            XCTAssertEqual(row.deletions, 80)
        }
    }

    func test_loc_keep_old_when_new_total_lower() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(additions: 500, deletions: 200), in: db)
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(additions: 10, deletions: 5), in: db)
            let row = try GitHubLOCWeeklyRow.fetchOne(db)!
            XCTAssertEqual(row.additions, 500)
            XCTAssertEqual(row.deletions, 200)
        }
    }

    func test_loc_keep_old_when_new_total_equal() throws {
        try dbq.write { db in
            var first = makeLOCRow(additions: 100, deletions: 50)
            first.updatedAt = "2024-01-01T00:00:00Z"
            try NeverDecreaseUpserter.upsertGitHubLOC(first, in: db)
            var second = makeLOCRow(additions: 100, deletions: 50)
            second.updatedAt = "2024-12-31T00:00:00Z"
            try NeverDecreaseUpserter.upsertGitHubLOC(second, in: db)
            let row = try GitHubLOCWeeklyRow.fetchOne(db)!
            XCTAssertEqual(row.updatedAt, "2024-01-01T00:00:00Z")
        }
    }

    func test_loc_different_weeks_same_repo_coexist() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(weekStart: "2024-05-19"), in: db)
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(weekStart: "2024-05-26"), in: db)
            XCTAssertEqual(try GitHubLOCWeeklyRow.fetchCount(db), 2)
        }
    }

    func test_loc_different_repos_same_week_coexist() throws {
        try dbq.write { db in
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(repo: "popovs/x"), in: db)
            try NeverDecreaseUpserter.upsertGitHubLOC(makeLOCRow(repo: "popovs/y"), in: db)
            XCTAssertEqual(try GitHubLOCWeeklyRow.fetchCount(db), 2)
        }
    }
}
