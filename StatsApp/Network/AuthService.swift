import Foundation

/// Узкий протокол для ViewModel — чтобы тестировать VM с fake-входом.
protocol GitHubSignInService {
    func signIn(provider: String, includePrivate: Bool) async throws -> AuthExchangeResponse
}

/// Оркестрирует OAuth-флоу: start URL → ASWebAuthenticationSession → exchange.
final class AuthService: GitHubSignInService {
    private let authBaseURL: URL
    private let api: AiuseAPIClient
    private let webAuth: WebAuthenticating

    static let callbackScheme = "burn"

    init(authBaseURL: URL, api: AiuseAPIClient, webAuth: WebAuthenticating) {
        self.authBaseURL = authBaseURL
        self.api = api
        self.webAuth = webAuth
    }

    func signIn(provider: String, includePrivate: Bool) async throws -> AuthExchangeResponse {
        let verifier = Crypto.randomVerifier()
        let challenge = Crypto.sha256Hex(verifier)

        var startURL = authBaseURL
        startURL.append(path: "/auth/start")
        guard var components = URLComponents(url: startURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.badCallbackURL(startURL.absoluteString)
        }
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "challenge", value: challenge),
            URLQueryItem(name: "include_private", value: includePrivate ? "true" : "false"),
        ]
        guard let finalStart = components.url else {
            throw AuthError.badCallbackURL(startURL.absoluteString)
        }

        let callback = try await webAuth.authenticate(
            url: finalStart, callbackScheme: Self.callbackScheme
        )

        guard let cc = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = cc.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw AuthError.noCodeInCallback
        }

        return try await api.exchange(code: code, verifier: verifier)
    }
}
