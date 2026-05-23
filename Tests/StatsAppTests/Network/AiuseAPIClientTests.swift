import XCTest
@testable import StatsApp

final class AiuseAPIClientTests: XCTestCase {
    var client: AiuseAPIClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        client = AiuseAPIClient(
            baseURL: URL(string: "https://test.local/api")!,
            secretProvider: { "test-secret" },
            session: session
        )
        MockURLProtocol.responder = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.lastBody = nil
    }

    func testCreateProfile_sendsBodyWithoutAuthHeader() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles")!,
                statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = #"{"friend_code":"XK7P3M9Q2A","api_secret":"deadbeef","server_user_id":42}"#
            return (resp, json.data(using: .utf8)!)
        }
        let result = try await client.createProfile(displayName: "Серёжа")
        XCTAssertEqual(result.friendCode, "XK7P3M9Q2A")
        XCTAssertEqual(result.apiSecret, "deadbeef")
        XCTAssertEqual(result.serverUserId, 42)

        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.url?.path, "/api/profiles")
        XCTAssertNil(req?.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let decoded = try JSONDecoder().decode([String: String?].self, from: body)
        XCTAssertEqual(decoded["display_name"], "Серёжа")
    }

    func testCreateProfile_with4xx_throwsHTTPError() async {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles")!,
                statusCode: 422, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("validation failed".utf8))
        }
        do {
            _ = try await client.createProfile(displayName: "")
            XCTFail("expected error")
        } catch let AiuseAPIError.http(status, _) {
            XCTAssertEqual(status, 422)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSendSnapshots_putsBearerAndBody() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/snapshots")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(#"{"accepted":1}"#.utf8))
        }
        let result = try await client.sendSnapshots([
            SnapshotItem(hourBucket: "2026-05-23T00:00:00Z", tokensInput: 100, tokensOutput: 200)
        ])
        XCTAssertEqual(result.accepted, 1)
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer test-secret")
    }

    func testRegenerateFriendCode_returnsNewCode() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me/regenerate-friend-code")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(#"{"friend_code":"NEW1234567","friendships_dropped":3}"#.utf8))
        }
        let result = try await client.regenerateFriendCode()
        XCTAssertEqual(result.friendCode, "NEW1234567")
        XCTAssertEqual(result.friendshipsDropped, 3)
    }

    func testDeleteAccount_sendsDelete() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me")!,
                statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        try await client.deleteAccount()
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "DELETE")
    }

    func testMissingSecret_throwsImmediately() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let clientNoSecret = AiuseAPIClient(
            baseURL: URL(string: "https://test.local/api")!,
            secretProvider: { nil },
            session: session
        )
        do {
            _ = try await clientNoSecret.sendSnapshots([])
            XCTFail("expected missingSecret")
        } catch AiuseAPIError.missingSecret {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    // MARK: - leaderboard previous_rank

    func testGetLeaderboard_decodes_previousRank_when_present() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/leaderboard?period=week")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = """
            {
              "period": "week",
              "as_of": "2024-05-22T12:00:00Z",
              "entries": [
                {"friend_code":"AAA","display_name":"Сергей","rank":1,"previous_rank":3,"tokens_total":12000,"is_me":false},
                {"friend_code":"BBB","display_name":"Я","rank":2,"previous_rank":null,"tokens_total":8000,"is_me":true}
              ]
            }
            """
            return (resp, json.data(using: .utf8)!)
        }
        let resp = try await client.getLeaderboard(period: "week")
        XCTAssertEqual(resp.entries[0].previousRank, 3)
        XCTAssertNil(resp.entries[1].previousRank)
    }

    func testGetLeaderboard_decodes_previousRank_as_nil_when_field_missing() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/leaderboard?period=day")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            // Без previous_rank — старый формат бэкенда, до раскатки.
            let json = """
            {
              "period": "day",
              "as_of": "2024-05-22T12:00:00Z",
              "entries": [
                {"friend_code":"AAA","display_name":"Сергей","rank":1,"tokens_total":100,"is_me":false}
              ]
            }
            """
            return (resp, json.data(using: .utf8)!)
        }
        let resp = try await client.getLeaderboard(period: "day")
        XCTAssertNil(resp.entries[0].previousRank)
    }
}
