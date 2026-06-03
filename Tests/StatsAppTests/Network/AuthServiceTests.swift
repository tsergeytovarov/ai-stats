import XCTest
@testable import StatsApp

private final class FakeWebAuth: WebAuthenticating {
    var capturedURL: URL?
    var callback: URL

    init(callback: URL) { self.callback = callback }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        capturedURL = url
        return callback
    }
}

final class AuthServiceTests: XCTestCase {
    private func makeAPI() -> AiuseAPIClient {
        MockURLProtocol.responder = { req in
            let body = """
            {"device_token":"dt","github_token":"ght","github_login":"octocat",
             "friend_code":"AAAA-BBBB-CC","server_user_id":7}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return AiuseAPIClient(
            baseURL: URL(string: "https://example.test/api")!,
            secretProvider: { nil },
            session: URLSession(configuration: cfg)
        )
    }

    func test_signIn_buildsStartURL_andExchangesCode() async throws {
        let fake = FakeWebAuth(callback: URL(string: "burn://auth/callback?code=AUTHCODE&state=st")!)
        let service = AuthService(
            authBaseURL: URL(string: "https://example.test/api")!,
            api: makeAPI(),
            webAuth: fake
        )

        let resp = try await service.signIn(provider: "github", includePrivate: false)

        XCTAssertEqual(resp.deviceToken, "dt")
        XCTAssertEqual(resp.githubLogin, "octocat")

        let start = fake.capturedURL!.absoluteString
        XCTAssertTrue(start.hasPrefix("https://example.test/api/auth/start"))
        XCTAssertTrue(start.contains("provider=github"))
        XCTAssertTrue(start.contains("challenge="))
        XCTAssertTrue(start.contains("include_private=false"))
    }

    func test_signIn_noCodeInCallback_throws() async {
        let fake = FakeWebAuth(callback: URL(string: "burn://auth/callback?state=st")!)
        let service = AuthService(
            authBaseURL: URL(string: "https://example.test/api")!,
            api: makeAPI(),
            webAuth: fake
        )
        do {
            _ = try await service.signIn(provider: "github", includePrivate: false)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? AuthError, .noCodeInCallback)
        }
    }
}
