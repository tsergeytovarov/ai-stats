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
}
