import XCTest
@testable import StatsApp

final class GitHubFetcherTests: XCTestCase {
    func test_parses_fixture_into_rows() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "github-response", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let rows = try GitHubResponseParser.parse(data, now: { ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")! })

        XCTAssertEqual(rows.count, 3)
        let aiStatsRows = rows.filter { $0.repo == "popovs/ai-stats" }
        XCTAssertEqual(aiStatsRows.count, 2)
        XCTAssertEqual(aiStatsRows.first { $0.day == "2024-05-20" }?.commits, 3)
        XCTAssertEqual(aiStatsRows.first { $0.day == "2024-05-21" }?.commits, 5)

        let otherRow = rows.first { $0.repo == "popovs/other" }!
        XCTAssertEqual(otherRow.day, "2024-05-20")
        XCTAssertEqual(otherRow.commits, 1)
        XCTAssertEqual(otherRow.updatedAt, "2024-05-22T10:00:00Z")
    }

    func test_graphql_errors_thrown() throws {
        let json = """
        { "errors": [{"message": "bad token"}] }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try GitHubResponseParser.parse(json, now: { Date() })) { error in
            guard case GitHubError.graphqlErrors(let messages) = error else {
                return XCTFail("expected graphqlErrors, got \(error)")
            }
            XCTAssertEqual(messages, ["bad token"])
        }
    }

    func test_zero_commit_days_skipped() throws {
        let json = """
        { "data": { "viewer": { "contributionsCollection": { "commitContributionsByRepository": [
          { "repository": {"nameWithOwner": "popovs/x"}, "contributions": { "nodes": [
            {"occurredAt": "2024-05-20T00:00:00Z", "commitCount": 0},
            {"occurredAt": "2024-05-21T00:00:00Z", "commitCount": 2}
          ]}}
        ]}}}}
        """.data(using: .utf8)!
        let rows = try GitHubResponseParser.parse(json, now: { Date() })
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].day, "2024-05-21")
    }

    // MARK: - Commit history LOC aggregation

    func test_commit_history_parses_into_daily_loc() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "github-commit-history", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let response = try JSONDecoder().decode(CommitHistoryResponse.self, from: data)

        XCTAssertNil(response.errors)
        let nodes = response.data?.repository?.defaultBranchRef?.target?.history?.nodes ?? []
        XCTAssertEqual(nodes.count, 3)

        let aggregated = GitHubResponseParser.aggregateCommitsByDay(nodes)
        XCTAssertEqual(aggregated.count, 2)

        let byDay = Dictionary(uniqueKeysWithValues: aggregated.map { ($0.day, $0) })
        // May 20: 50+20 = 70 additions, 10+5 = 15 deletions
        XCTAssertEqual(byDay["2024-05-20"]?.add, 70)
        XCTAssertEqual(byDay["2024-05-20"]?.del, 15)
        // May 21: 100 additions, 0 deletions
        XCTAssertEqual(byDay["2024-05-21"]?.add, 100)
        XCTAssertEqual(byDay["2024-05-21"]?.del, 0)
    }

    func test_aggregate_single_day_multiple_commits() {
        let nodes: [CommitHistoryResponse.Node] = [
            CommitHistoryResponse.Node(committedDate: "2024-05-22T08:00:00Z", additions: 30, deletions: 10),
            CommitHistoryResponse.Node(committedDate: "2024-05-22T14:00:00Z", additions: 70, deletions: 20),
        ]
        let result = GitHubResponseParser.aggregateCommitsByDay(nodes)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].day, "2024-05-22")
        XCTAssertEqual(result[0].add, 100)
        XCTAssertEqual(result[0].del, 30)
    }

    func test_aggregate_empty_nodes_returns_empty() {
        let result = GitHubResponseParser.aggregateCommitsByDay([])
        XCTAssertTrue(result.isEmpty)
    }
}
