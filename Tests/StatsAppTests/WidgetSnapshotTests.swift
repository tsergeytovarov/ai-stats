import XCTest
@testable import StatsApp

final class WidgetSnapshotTests: XCTestCase {
    func test_decode_legacy_json_without_new_fields_uses_defaults() throws {
        // JSON в старом формате — без aiCostPrev, leaderboard, myFriendCode.
        let json = """
        {
            "generatedAt": "2026-05-23T12:00:00Z",
            "githubEnabled": true,
            "day":   { "aiCost": 10.0, "aiTokens": 100, "commits": 1, "uniqueRepos": 1, "topModels": [] },
            "week":  { "aiCost": 50.0, "aiTokens": 500, "commits": 5, "uniqueRepos": 2, "topModels": [] },
            "month": { "aiCost": 200.0, "aiTokens": 2000, "commits": 20, "uniqueRepos": 3, "topModels": [] }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(snapshot.day.aiCost, 10.0)
        XCTAssertEqual(snapshot.day.aiCostPrev, 0.0)
        XCTAssertNil(snapshot.day.leaderboard)
        XCTAssertNil(snapshot.myFriendCode)
    }

    func test_roundtrip_with_full_leaderboard_slice() throws {
        let me = WidgetSnapshot.LeaderboardSlice.Entry(
            rank: 42, previousRank: 50, displayName: "Я", tokensTotal: 200, isMe: true
        )
        let lb = WidgetSnapshot.LeaderboardSlice(
            entries: [
                .init(rank: 1, previousRank: 11, displayName: "Серёжа", tokensTotal: 12_400, isMe: false),
                .init(rank: 2, previousRank: 5,  displayName: "Вася",    tokensTotal: 9_800,  isMe: false),
            ],
            meExtra: me
        )
        let slice = WidgetSnapshot.PeriodSlice(
            aiCost: 250.0, aiCostPrev: 222.40,
            aiTokens: 12_400_000, commits: 5, uniqueRepos: 2,
            topModels: [], leaderboard: lb
        )
        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_716_336_000),
            day: slice, week: slice, month: slice,
            githubEnabled: true,
            myFriendCode: "abc123"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.day.leaderboard?.meExtra?.rank, 42)
        XCTAssertEqual(decoded.myFriendCode, "abc123")
    }

    func test_decode_legacy_json_with_partial_period_slice() throws {
        // PeriodSlice без leaderboard и aiCostPrev — должны дефолтиться.
        let json = """
        {
            "generatedAt": "2026-05-23T12:00:00Z",
            "githubEnabled": false,
            "day":   { "aiCost": 5.0, "aiTokens": 50, "commits": 0, "uniqueRepos": 0, "topModels": [] },
            "week":  { "aiCost": 5.0, "aiTokens": 50, "commits": 0, "uniqueRepos": 0, "topModels": [] },
            "month": { "aiCost": 5.0, "aiTokens": 50, "commits": 0, "uniqueRepos": 0, "topModels": [] }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: json)
        XCTAssertEqual(snapshot.day.aiCostPrev, 0)
        XCTAssertNil(snapshot.day.leaderboard)
    }
}
