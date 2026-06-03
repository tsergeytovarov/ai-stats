import Foundation

enum AuthError: Error, LocalizedError, Equatable {
    case cancelled
    case cannotStart
    case noCodeInCallback
    case badCallbackURL(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Вход отменён"
        case .cannotStart: return "Не удалось запустить вход"
        case .noCodeInCallback: return "Сервер вернул некорректный ответ авторизации"
        case .badCallbackURL(let s): return "Некорректный callback: \(s)"
        }
    }
}
