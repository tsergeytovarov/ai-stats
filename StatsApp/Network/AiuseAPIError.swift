import Foundation

enum AiuseAPIError: LocalizedError, Equatable {
    case missingSecret           // нет в Keychain
    case invalidURL
    case invalidFriendCode(String)   // friend_code не прошёл клиентскую валидацию
    case transport(String)       // network failure
    case http(status: Int, body: String)
    case decoding(String)
    case unexpected
    case responseTooLarge(bytes: Int)        // JSON-ответ от aiuse превысил кап
    case avatarTooLarge(bytes: Int)          // ответ /avatars превысил кап
    case avatarBadMime(mime: String)         // не из allowlist {image/png, image/jpeg}

    var errorDescription: String? {
        switch self {
        case .missingSecret:
            return "api_secret отсутствует в Keychain (создай аккаунт в Settings → Аккаунт)"
        case .invalidURL:
            return "некорректный URL запроса"
        case .invalidFriendCode(let raw):
            return "friend_code должен быть 10 ASCII-символов из [A-Z0-9] (получено: \"\(raw)\")"
        case .transport(let msg):
            return "сетевая ошибка: \(msg)"
        case .http(let status, let body):
            let short = body.isEmpty ? "" : " — \(body.prefix(120))"
            return "HTTP \(status)\(short)"
        case .decoding(let msg):
            return "не удалось разобрать ответ: \(msg)"
        case .unexpected:
            return "неожиданный ответ сервера"
        case .responseTooLarge(let bytes):
            return "ответ сервера слишком большой (\(bytes) байт). Возможно сервер скомпрометирован."
        case .avatarTooLarge(let bytes):
            return "аватарка слишком большая (\(bytes) байт). Максимум — 512 KB."
        case .avatarBadMime(let mime):
            return "неожиданный MIME-тип аватарки: \"\(mime)\". Ожидался image/png или image/jpeg."
        }
    }
}
