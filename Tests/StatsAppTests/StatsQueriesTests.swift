import XCTest
import GRDB
@testable import StatsApp

final class StatsQueriesTests: XCTestCase {
    var dbq: DatabaseQueue!

    override func setUpWithError() throws {
        dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try seed()
    }

    private func seed() throws {
        try dbq.write { db in
            let ai = [
                AIUsageRow(id: nil, day: "2024-05-22", source: "claude", modelsJson: "[]", inputTokens: 100, outputTokens: 50, costUsd: 2.0, updatedAt: "now"),
                AIUsageRow(id: nil, day: "2024-05-22", source: "codex", modelsJson: "[]", inputTokens: 200, outputTokens: 100, costUsd: 3.0, updatedAt: "now"),
                AIUsageRow(id: nil, day: "2024-05-20", source: "claude", modelsJson: "[]", inputTokens: 80, outputTokens: 20, costUsd: 1.5, updatedAt: "now"),
            ]
            for var row in ai { try row.insert(db) }

            let gh = [
                GitHubRow(id: nil, day: "2024-05-22", repo: "popovs/x", commits: 3, updatedAt: "now"),
                GitHubRow(id: nil, day: "2024-05-22", repo: "popovs/y", commits: 2, updatedAt: "now"),
                GitHubRow(id: nil, day: "2024-05-20", repo: "popovs/x", commits: 7, updatedAt: "now"),
            ]
            for var row in gh { try row.insert(db) }
        }
    }

    func test_aiTotals_for_single_day() throws {
        let totals = try dbq.read { db in
            try StatsQueries.aiTotals(in: db, days: ["2024-05-22"])
        }
        XCTAssertEqual(totals.totalCost, 5.0, accuracy: 0.001)
        XCTAssertEqual(totals.totalInputTokens, 300)
        XCTAssertEqual(totals.totalOutputTokens, 150)
    }

    func test_aiTotalsBySource_groups_per_source() throws {
        let bySource = try dbq.read { db in
            try StatsQueries.aiTotalsBySource(in: db, days: ["2024-05-22"])
        }
        XCTAssertEqual(bySource.count, 2)
        XCTAssertEqual(bySource.first { $0.source == "claude" }?.costUsd, 2.0)
        XCTAssertEqual(bySource.first { $0.source == "codex" }?.costUsd, 3.0)
    }

    func test_githubTotals_returns_commits_and_repo_count() throws {
        let totals = try dbq.read { db in
            try StatsQueries.githubTotals(in: db, days: ["2024-05-22"])
        }
        XCTAssertEqual(totals.totalCommits, 5)
        XCTAssertEqual(totals.uniqueRepos, 2)
    }

    func test_dailyCostSparkline_returns_dense_array() throws {
        let series = try dbq.read { db in
            try StatsQueries.dailyAICostSeries(in: db, days: ["2024-05-20", "2024-05-21", "2024-05-22"])
        }
        XCTAssertEqual(series, [1.5, 0.0, 5.0])
    }

    // MARK: - githubLOC

    private func seedLOC() throws {
        try dbq.write { db in
            // Week of 2024-05-19 (Sunday)
            var r1 = GitHubLOCWeeklyRow(id: nil, weekStart: "2024-05-19", repo: "popovs/x", additions: 120, deletions: 30, updatedAt: "now")
            try r1.insert(db)
            var r2 = GitHubLOCWeeklyRow(id: nil, weekStart: "2024-05-19", repo: "popovs/y", additions: 50, deletions: 10, updatedAt: "now")
            try r2.insert(db)
            // Week of 2024-05-26
            var r3 = GitHubLOCWeeklyRow(id: nil, weekStart: "2024-05-26", repo: "popovs/x", additions: 200, deletions: 80, updatedAt: "now")
            try r3.insert(db)
        }
    }

    func test_githubLOC_sums_weeks_covering_days() throws {
        try seedLOC()
        // 2024-05-22 (Wed) → week start 2024-05-19 → additions 120+50=170, deletions 30+10=40
        let loc = try dbq.read { db in
            try StatsQueries.githubLOC(in: db, days: ["2024-05-22"])
        }
        XCTAssertEqual(loc.additions, 170)
        XCTAssertEqual(loc.deletions, 40)
    }

    func test_githubLOC_spans_two_weeks() throws {
        try seedLOC()
        // 2024-05-22 → week 2024-05-19; 2024-05-28 (Tue) → week 2024-05-26
        let loc = try dbq.read { db in
            try StatsQueries.githubLOC(in: db, days: ["2024-05-22", "2024-05-28"])
        }
        XCTAssertEqual(loc.additions, 170 + 200)
        XCTAssertEqual(loc.deletions, 40 + 80)
    }

    func test_githubLOC_empty_days_returns_zeros() throws {
        try seedLOC()
        let loc = try dbq.read { db in
            try StatsQueries.githubLOC(in: db, days: [])
        }
        XCTAssertEqual(loc.additions, 0)
        XCTAssertEqual(loc.deletions, 0)
    }

    func test_githubLOC_no_data_for_days_returns_zeros() throws {
        try seedLOC()
        // 2024-01-01 → week 2023-12-31 — no data
        let loc = try dbq.read { db in
            try StatsQueries.githubLOC(in: db, days: ["2024-01-01"])
        }
        XCTAssertEqual(loc.additions, 0)
        XCTAssertEqual(loc.deletions, 0)
    }

    // MARK: - topModels

    private func seedModelRows() throws {
        try dbq.write { db in
            let rows: [AIUsageModelRow] = [
                AIUsageModelRow(id: nil, day: "2024-05-22", source: "claude", model: "claude-opus-4-7",    inputTokens: 1000, outputTokens: 500,  costUsd: 10.0, updatedAt: "now"),
                AIUsageModelRow(id: nil, day: "2024-05-22", source: "claude", model: "claude-sonnet-4-6",  inputTokens: 500,  outputTokens: 200,  costUsd: 3.0,  updatedAt: "now"),
                AIUsageModelRow(id: nil, day: "2024-05-22", source: "codex",  model: "gpt-5.5",            inputTokens: 300,  outputTokens: 100,  costUsd: 5.0,  updatedAt: "now"),
                AIUsageModelRow(id: nil, day: "2024-05-20", source: "claude", model: "claude-opus-4-7",    inputTokens: 800,  outputTokens: 300,  costUsd: 8.0,  updatedAt: "now"),
                AIUsageModelRow(id: nil, day: "2024-05-20", source: "codex",  model: "codex-auto-review",  inputTokens: 200,  outputTokens: 80,   costUsd: 1.0,  updatedAt: "now"),
            ]
            for var row in rows { try row.insert(db) }
        }
    }

    func test_topModels_orders_by_cost_desc_and_limits() throws {
        try seedModelRows()
        let top2 = try dbq.read { db in
            try StatsQueries.topModels(in: db, days: ["2024-05-22", "2024-05-20"], limit: 2)
        }
        // claude-opus-4-7 appears on both days: 10 + 8 = 18 total
        // gpt-5.5: 5, claude-sonnet: 3, codex-auto-review: 1
        XCTAssertEqual(top2.count, 2)
        XCTAssertEqual(top2[0].model, "claude-opus-4-7")
        XCTAssertEqual(top2[0].costUsd, 18.0, accuracy: 0.001)
        XCTAssertEqual(top2[1].model, "gpt-5.5")
        XCTAssertEqual(top2[1].costUsd, 5.0, accuracy: 0.001)
    }

    func test_topModels_empty_days_returns_empty() throws {
        try seedModelRows()
        let result = try dbq.read { db in
            try StatsQueries.topModels(in: db, days: [])
        }
        XCTAssertTrue(result.isEmpty)
    }

    func test_topModels_filters_by_days() throws {
        try seedModelRows()
        // Only 2024-05-20 — opus(8), codex-auto-review(1)
        let result = try dbq.read { db in
            try StatsQueries.topModels(in: db, days: ["2024-05-20"], limit: 5)
        }
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].model, "claude-opus-4-7")
        XCTAssertEqual(result[0].costUsd, 8.0, accuracy: 0.001)
    }
}
