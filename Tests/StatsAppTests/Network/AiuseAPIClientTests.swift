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

    // MARK: - getAvatar: MIME + size caps

    /// Хелпер: HTTPURLResponse для /avatars с заданным mime и опц. Content-Length.
    private func avatarResponse(mime: String, contentLength: Int? = nil, status: Int = 200) -> HTTPURLResponse {
        var headers: [String: String] = ["Content-Type": mime, "ETag": "W/\"abc\""]
        if let contentLength {
            headers["Content-Length"] = String(contentLength)
        }
        return HTTPURLResponse(
            url: URL(string: "https://test.local/api/avatars/XK7P3M9Q2A")!,
            statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
    }

    func testGetAvatar_acceptsImagePNG() async throws {
        let body = Data(repeating: 0x42, count: 100)
        MockURLProtocol.responder = { _ in
            return (self.avatarResponse(mime: "image/png", contentLength: body.count), body)
        }
        let result = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
        XCTAssertEqual(result?.data, body)
        XCTAssertEqual(result?.mime, "image/png")
    }

    func testGetAvatar_acceptsImageJPEG() async throws {
        let body = Data(repeating: 0x55, count: 100)
        MockURLProtocol.responder = { _ in
            return (self.avatarResponse(mime: "image/jpeg", contentLength: body.count), body)
        }
        let result = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
        XCTAssertEqual(result?.mime, "image/jpeg")
    }

    func testGetAvatar_stripsCharsetSuffixFromMime() async throws {
        let body = Data(repeating: 0x42, count: 50)
        MockURLProtocol.responder = { _ in
            return (self.avatarResponse(mime: "image/png; charset=binary"), body)
        }
        let result = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
        XCTAssertEqual(result?.mime, "image/png", "charset-довесок отрезается, в стораджа MIME без него")
    }

    func testGetAvatar_rejectsHtmlMime() async {
        MockURLProtocol.responder = { _ in
            return (self.avatarResponse(mime: "text/html"), Data("<script>".utf8))
        }
        do {
            _ = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
            XCTFail("ожидали avatarBadMime")
        } catch AiuseAPIError.avatarBadMime(let mime) {
            XCTAssertEqual(mime, "text/html")
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testGetAvatar_rejectsImageSvgXml() async {
        // SVG может содержать JS / external refs — отдельный класс уязвимостей, не пускаем.
        MockURLProtocol.responder = { _ in
            return (self.avatarResponse(mime: "image/svg+xml"), Data("<svg/>".utf8))
        }
        do {
            _ = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
            XCTFail("ожидали avatarBadMime")
        } catch AiuseAPIError.avatarBadMime {
            // OK
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testGetAvatar_rejectsViaContentLengthPrecheck() async {
        // Сервер заявляет в Content-Length, что ответ огромный → отваливаемся ДО чтения тела.
        MockURLProtocol.responder = { _ in
            let big = 600 * 1024  // > 512 KB кап
            return (self.avatarResponse(mime: "image/png", contentLength: big), Data())
        }
        do {
            _ = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
            XCTFail("ожидали avatarTooLarge")
        } catch AiuseAPIError.avatarTooLarge(let bytes) {
            XCTAssertGreaterThan(bytes, 512 * 1024)
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testGetAvatar_rejectsViaStreamCap() async {
        // Сервер врёт в Content-Length (или его нет), но реально шлёт > 512 KB.
        // Streaming-cap режет на лету.
        let bigBody = Data(repeating: 0xAA, count: 600 * 1024)
        MockURLProtocol.responder = { _ in
            // Намеренно без Content-Length чтобы выйти на streaming-чтение.
            return (self.avatarResponse(mime: "image/png", contentLength: nil), bigBody)
        }
        do {
            _ = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
            XCTFail("ожидали avatarTooLarge")
        } catch AiuseAPIError.avatarTooLarge {
            // OK
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testGetAvatar_passes304Through() async throws {
        MockURLProtocol.responder = { _ in
            // 304 — нет тела, MIME-чек не должен сработать.
            return (self.avatarResponse(mime: "", status: 304), Data())
        }
        let result = try await client.getAvatar(friendCode: "XK7P3M9Q2A", ifNoneMatch: "W/\"abc\"")
        XCTAssertNil(result, "304 → nil")
    }

    func testGetAvatar_passes404Through() async throws {
        MockURLProtocol.responder = { _ in
            return (self.avatarResponse(mime: "", status: 404), Data())
        }
        let result = try await client.getAvatar(friendCode: "XK7P3M9Q2A")
        XCTAssertNil(result, "404 → nil")
    }

}
