import XCTest
@testable import StatsApp

final class WidgetSnapshotTests: XCTestCase {
    func test_decode_legacy_json_missing_schemaVersion_treatedAsV1() throws {
        // Снапшот старого app'а: без schemaVersion, с полями github/leaderboard.
        // Лишние ключи игнорируются, отсутствующий schemaVersion → 1 (legacy).
        let json = """
        {
            "generatedAt": "2026-05-23T12:00:00Z",
            "githubEnabled": true,
            "myFriendCode": "abc123",
            "day":   { "aiCost": 10.0, "aiTokens": 100, "commits": 1, "uniqueRepos": 1, "topModels": [], "leaderboard": null },
            "week":  { "aiCost": 50.0, "aiTokens": 500, "commits": 5, "uniqueRepos": 2, "topModels": [] },
            "month": { "aiCost": 200.0, "aiTokens": 2000, "commits": 20, "uniqueRepos": 3, "topModels": [] }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.day.aiCost, 10.0)
        XCTAssertEqual(snapshot.day.aiCostPrev, 0.0)  // decodeIfPresent → 0
    }

    func test_roundtrip_preserves_ai_fields_and_schemaVersion() throws {
        let slice = WidgetSnapshot.PeriodSlice(
            aiCost: 250.0, aiCostPrev: 222.40, aiTokens: 12_400_000,
            topModels: [
                WidgetSnapshot.ModelEntry(model: "claude-opus-4-8", source: "claude", costUsd: 200, inputTokens: 10, outputTokens: 20)
            ]
        )
        let snapshot = WidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_716_336_000),
            day: slice, week: slice, month: slice
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.day.aiCostPrev, 222.40, accuracy: 0.001)
        XCTAssertEqual(decoded.day.topModels.first?.model, "claude-opus-4-8")
    }

    func test_decode_v2_json_without_prevCost_defaultsToZero() throws {
        let json = """
        {
            "schemaVersion": 2,
            "generatedAt": "2026-05-23T12:00:00Z",
            "day":   { "aiCost": 5.0, "aiTokens": 50, "topModels": [] },
            "week":  { "aiCost": 5.0, "aiTokens": 50, "topModels": [] },
            "month": { "aiCost": 5.0, "aiTokens": 50, "topModels": [] }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: json)
        XCTAssertEqual(snapshot.schemaVersion, 2)
        XCTAssertEqual(snapshot.day.aiCostPrev, 0)
    }
}
