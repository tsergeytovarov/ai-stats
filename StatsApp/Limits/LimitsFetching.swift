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
