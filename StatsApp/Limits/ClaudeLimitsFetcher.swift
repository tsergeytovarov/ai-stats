import Foundation

/// Лимиты Claude через недокументированный OAuth-эндпоинт. Токен читаем из чужой
/// записи Keychain (её пишет Claude Code) и нигде не сохраняем: взяли, сходили,
/// забыли. Эндпоинт жёстко троттлится — живой ответ отдал Retry-After 3582,
/// поэтому расписание опроса часовое, а 429 обязан уважаться.
final class ClaudeLimitsFetcher: LimitsFetching {
    let provider: LimitProvider = .claude

    static let keychainService = "Claude Code-credentials"
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let betaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.1.0"

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
        guard let blob = keychain.get(account: account, service: Self.keychainService),
              let token = ClaudeUsageParser.tokenFromKeychainBlob(blob) else {
            return .failure(.claude, status: .unauthorized, error: "нет токена Claude Code")
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.claude, status: .stale, error: "неожиданный ответ")
            }
            switch http.statusCode {
            case 200:
                let windows = ClaudeUsageParser.parse(data)
                guard !windows.isEmpty else {
                    // 200 без окон — эндпоинт сменил форму, а не лимиты кончились.
                    return .failure(.claude, status: .unavailable, error: "не разобрал ответ")
                }
                return ProviderLimits(provider: .claude, windows: windows, status: .ok,
                                      fetchedAt: now(), error: nil)
            case 401, 403:
                return .failure(.claude, status: .unauthorized, error: "нужен вход заново")
            case 429:
                return .failure(.claude, status: .throttled, error: "лимит запросов, ждём",
                                retryAfter: Self.retryAfterDate(
                                    from: http.value(forHTTPHeaderField: "Retry-After"),
                                    now: now()))
            default:
                return .failure(.claude, status: .stale, error: "HTTP \(http.statusCode)")
            }
        } catch {
            return .failure(.claude, status: .stale, error: error.localizedDescription)
        }
    }

    /// Retry-After приходит в секундах. Нет заголовка — считаем час: наблюдаемое
    /// окно троттлинга примерно такое.
    static func retryAfterDate(from header: String?, now: Date) -> Date {
        let seconds = header.flatMap(TimeInterval.init) ?? 3600
        return now.addingTimeInterval(seconds)
    }
}
