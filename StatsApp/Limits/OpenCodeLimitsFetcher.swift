import Foundation

/// Лимиты подписки OpenCode Go. API-ключи из ~/.local/share/opencode/auth.json не
/// подходят — они дают модели, а не квоту. Нужна сессионная cookie сайта, её
/// пользователь вставляет в настройках, лежит в Keychain.
final class OpenCodeLimitsFetcher: LimitsFetching {
    let provider: LimitProvider = .opencode

    static let keychainService = "ai-stats.opencode"

    private static let base = "https://opencode.ai"
    private static let workspacesServerID =
        "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
    // Cloudflare рубит дефолтный UA URLSession — ходим браузерным.
    private static let userAgent = """
    Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 \
    (KHTML, like Gecko) Chrome/124.0 Safari/537.36
    """

    private let keychain: KeychainStore
    private let account: String
    private let session: URLSession
    private let now: @Sendable () -> Date

    init(keychain: KeychainStore = MacOSKeychainStore(),
         account: String = NSUserName(),
         session: URLSession = .shared,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.keychain = keychain
        self.account = account
        self.session = session
        self.now = now
    }

    func fetch() async -> ProviderLimits {
        let stored = keychain.get(account: account, service: Self.keychainService) ?? ""
        let cookie = OpenCodeUsageParser.filterAuthCookie(
            OpenCodeUsageParser.normalizeCookie(stored))
        guard !cookie.isEmpty else {
            return .failure(.opencode, status: .unconfigured, error: "нет cookie opencode.ai")
        }

        do {
            let discovery = try await get(
                url: URL(string: "\(Self.base)/_server?id=\(Self.workspacesServerID)")!,
                cookie: cookie,
                accept: "text/javascript, application/json;q=0.9, */*;q=0.8",
                extra: ["X-Server-Id": Self.workspacesServerID,
                        "X-Server-Instance": "server-fn:\(UUID().uuidString)"])
            let ids = OpenCodeUsageParser.parseWorkspaceIDs(discovery)
            guard !ids.isEmpty else {
                // Пустой список воркспейсов — почти всегда протухшая cookie.
                return .failure(.opencode, status: .unauthorized, error: "не нашёл воркспейс")
            }

            for id in ids {
                let page = try await get(url: URL(string: "\(Self.base)/workspace/\(id)/go")!,
                                         cookie: cookie,
                                         accept: "text/html,application/xhtml+xml,*/*;q=0.8",
                                         extra: [:])
                if let windows = OpenCodeUsageParser.parseLimits(page, now: now()) {
                    return ProviderLimits(provider: .opencode, windows: windows, status: .ok,
                                          fetchedAt: now(), error: nil)
                }
            }
            return .failure(.opencode, status: .unavailable, error: "не разобрал страницу")
        } catch let error as HTTPStatusError where error.code == 401 || error.code == 403 {
            return .failure(.opencode, status: .unauthorized, error: "cookie протухла")
        } catch {
            return .failure(.opencode, status: .stale, error: error.localizedDescription)
        }
    }

    private struct HTTPStatusError: Error { let code: Int }

    private func get(url: URL, cookie: String, accept: String,
                     extra: [String: String]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.base, forHTTPHeaderField: "Origin")
        request.setValue(Self.base, forHTTPHeaderField: "Referer")
        for (key, value) in extra { request.setValue(value, forHTTPHeaderField: key) }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPStatusError(code: http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
