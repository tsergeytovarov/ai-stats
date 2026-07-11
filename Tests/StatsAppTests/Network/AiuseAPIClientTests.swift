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

    func testGetMyProfile_putsBearer() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = #"{"friend_code":"XK7P3M9Q2A","display_name":"Я","sharing_enabled":true,"global_opt_in":false,"created_at":"2026-05-24T10:00:00Z"}"#
            return (resp, Data(json.utf8))
        }
        let result = try await client.getMyProfile()
        XCTAssertEqual(result.friendCode, "XK7P3M9Q2A")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer test-secret")
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
            _ = try await clientNoSecret.getMyProfile()
            XCTFail("expected missingSecret")
        } catch AiuseAPIError.missingSecret {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    // MARK: - request: response size cap

    func testRequest_rejectsHugeJSONViaContentLength() async {
        // Сервер заявляет о 2 MB → отваливаемся ДО чтения тела.
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me")!,
                statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json", "Content-Length": String(2 * 1024 * 1024)]
            )!
            return (resp, Data())
        }
        do {
            _ = try await client.getMyProfile()
            XCTFail("ожидали responseTooLarge")
        } catch AiuseAPIError.responseTooLarge(let bytes) {
            XCTAssertGreaterThan(bytes, 1024 * 1024)
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testRequest_rejectsHugeJSONViaStreamCap() async {
        // Без Content-Length, но реальный body > 1 MB.
        let bigBody = Data(repeating: 0x7B, count: 1_200_000) // 1.2 MB
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me")!,
                statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, bigBody)
        }
        do {
            _ = try await client.getMyProfile()
            XCTFail("ожидали responseTooLarge")
        } catch AiuseAPIError.responseTooLarge {
            // OK
        } catch {
            XCTFail("неожиданная ошибка: \(error)")
        }
    }

    func testRequest_passesSmallResponseThrough() async throws {
        // Регрессионный — на маленьких ответах ничего не сломалось после refactor'а на bytes(for:).
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me")!,
                statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = #"{"friend_code":"XK7P3M9Q2A","display_name":"Я","sharing_enabled":true,"global_opt_in":false,"created_at":"2026-05-24T10:00:00Z"}"#
            return (resp, Data(json.utf8))
        }
        let profile = try await client.getMyProfile()
        XCTAssertEqual(profile.displayName, "Я")
    }

    // MARK: - auth: exchange

    func test_exchange_postsCodeAndVerifier_returnsTokens() async throws {
        MockURLProtocol.responder = { req in
            let url = req.url!.absoluteString
            XCTAssertTrue(url.hasSuffix("/auth/exchange"))
            let body = """
            {"device_token":"dt","github_token":"ght","github_login":"octocat",
             "friend_code":"AAAA-BBBB-CC","server_user_id":7}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let api = AiuseAPIClient(
            baseURL: URL(string: "https://example.test/api")!,
            secretProvider: { nil },
            session: URLSession(configuration: cfg)
        )

        let resp = try await api.exchange(code: "AUTHCODE", verifier: "v123")

        XCTAssertEqual(resp.deviceToken, "dt")
        XCTAssertEqual(resp.githubToken, "ght")
        XCTAssertEqual(resp.githubLogin, "octocat")
        XCTAssertEqual(resp.serverUserId, 7)

        let sent = MockURLProtocol.lastBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(sent?["code"] as? String, "AUTHCODE")
        XCTAssertEqual(sent?["verifier"] as? String, "v123")
    }
}
