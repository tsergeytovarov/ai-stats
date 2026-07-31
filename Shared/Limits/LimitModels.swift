import Foundation

/// Провайдер подписки, у которого есть свой лимит.
enum LimitProvider: String, Codable, CaseIterable, Sendable {
    case claude, codex, opencode

    /// Короткая подпись под кольцом в капсуле.
    var shortTitle: String {
        switch self {
        case .claude:   return "cl"
        case .codex:    return "cx"
        case .opencode: return "oc"
        }
    }

    var displayTitle: String {
        switch self {
        case .claude:   return "Claude"
        case .codex:    return "Codex"
        case .opencode: return "OpenCode"
        }
    }
}

/// Окно лимита. Длительность приходит от источника — по позиции в ответе окна
/// не раскладываем: у Codex `primary` уже переехал с 5 часов на неделю.
struct LimitWindow: Codable, Equatable, Sendable {
    let windowMinutes: Int
    let usedPercent: Double
    let resetsAt: Date?
}

enum LimitStatus: String, Codable, Sendable {
    case ok            // цифры свежие
    case stale         // последний опрос не удался, показываем прошлые
    case throttled     // 429, ждём Retry-After
    case unauthorized  // токен/cookie протухли — нужно действие пользователя
    case unconfigured  // cookie не введена
    case unavailable   // источника нет (не установлен codex)
}

struct ProviderLimits: Codable, Equatable, Sendable {
    let provider: LimitProvider
    let windows: [LimitWindow]
    let status: LimitStatus
    let fetchedAt: Date?
    let error: String?
    /// Заполняется только при статусе throttled: до этого момента провайдера
    /// трогать нельзя. Живёт в результате, а не в изменяемом поле фетчера —
    /// иначе фетчер перестаёт быть Sendable.
    let retryAfter: Date?

    init(provider: LimitProvider, windows: [LimitWindow], status: LimitStatus,
         fetchedAt: Date?, error: String?, retryAfter: Date? = nil) {
        self.provider = provider
        self.windows = windows
        self.status = status
        self.fetchedAt = fetchedAt
        self.error = error
        self.retryAfter = retryAfter
    }
}

extension ProviderLimits {
    /// Окно, по которому заполняется кольцо: с самым ранним сбросом. Если времени
    /// сброса нет ни у одного окна — самое короткое по длительности.
    var ringWindow: LimitWindow? {
        let dated = windows.compactMap { w -> (Date, LimitWindow)? in
            guard let r = w.resetsAt else { return nil }
            return (r, w)
        }
        if let soonest = dated.min(by: { $0.0 < $1.0 })?.1 { return soonest }
        return windows.min(by: { $0.windowMinutes < $1.windowMinutes })
    }
}
