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

    // MARK: - LOC parser

    func test_loc_parser_filters_by_login() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "github-contributor-stats", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let fixedNow = ISO8601DateFormatter().date(from: "2024-05-22T10:00:00Z")!
        let rows = try GitHubResponseParser.parseLOCStats(
            data, repo: "popovs/ai-stats", login: "popovs", now: { fixedNow })

        // other-person's weeks should be excluded
        // popovs has 3 weeks but week with a=0 && d=0 should be skipped
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.repo == "popovs/ai-stats" })
    }

    func test_loc_parser_skips_zero_loc_weeks() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "github-contributor-stats", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let rows = try GitHubResponseParser.parseLOCStats(
            data, repo: "popovs/ai-stats", login: "popovs", now: { Date() })
        // None should have a=0 && d=0
        XCTAssertTrue(rows.allSatisfy { $0.additions > 0 || $0.deletions > 0 })
    }

    func test_loc_parser_maps_unix_to_iso_week_start() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "github-contributor-stats", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let rows = try GitHubResponseParser.parseLOCStats(
            data, repo: "popovs/ai-stats", login: "popovs", now: { Date() })
        // 1715990400 = 2024-05-18 00:00:00 UTC (Sunday)
        // 1717200000 = 2024-06-01 00:00:00 UTC (Saturday) — but we store isoDay of unix ts directly
        let weekStarts = Set(rows.map(\.weekStart))
        XCTAssertTrue(weekStarts.contains("2024-05-18"))
    }

    func test_loc_parser_case_insensitive_login() throws {
        let json = """
        [{"author": {"login": "POPOVS"}, "weeks": [{"w": 1715990400, "a": 10, "d": 5, "c": 1}]}]
        """.data(using: .utf8)!
        let rows = try GitHubResponseParser.parseLOCStats(
            json, repo: "popovs/x", login: "popovs", now: { Date() })
        XCTAssertEqual(rows.count, 1)
    }

    func test_loc_parser_unknown_login_returns_empty() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "github-contributor-stats", withExtension: "json")!
        let data = try Data(contentsOf: url)
        let rows = try GitHubResponseParser.parseLOCStats(
            data, repo: "popovs/ai-stats", login: "ghost", now: { Date() })
        XCTAssertEqual(rows.count, 0)
    }
}
