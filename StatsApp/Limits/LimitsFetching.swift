import Foundation

/// Источник лимитов одного провайдера. Реализации никогда не бросают — любая
/// беда превращается в ProviderLimits со статусом и пустыми окнами, чтобы
/// координатор не разбирал ошибки, а интерфейс показал честную плашку.
protocol LimitsFetching: Sendable {
    var provider: LimitProvider { get }
    func fetch() async -> ProviderLimits
}

extension ProviderLimits {
    /// Неудачный опрос без данных.
    static func failure(_ provider: LimitProvider, status: LimitStatus, error: String?,
                        retryAfter: Date? = nil) -> ProviderLimits {
        ProviderLimits(provider: provider, windows: [], status: status,
                       fetchedAt: nil, error: error, retryAfter: retryAfter)
    }
}

extension URLSession {
    /// Сессия для опроса лимитов: без системного cookie-хранилища. Приложение
    /// не в сэндбоксе, а `.shared` пишет любой Set-Cookie в
    /// ~/Library/Cookies/*.binarycookies мимо Keychain — cookie opencode.ai
    /// обязана жить только там (спека §8). Заодно `httpShouldSetCookies` не
    /// подмешивает системные куки к вручную выставленному заголовку Cookie,
    /// так что запрос остаётся детерминированным (находка 7 финального
    /// ревью).
    static func limitsFetching() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }
}
