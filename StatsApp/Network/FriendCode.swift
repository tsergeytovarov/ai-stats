import Foundation

/// Нормализация и валидация friend_code.
///
/// Формат на сервере — ровно 10 ASCII-символов из `[A-Z0-9]`. В UI код показывается
/// с дефисами (`XK7P-3M9Q-2A`), поэтому при вводе от пользователя дефисы и пробелы
/// сначала вычищаются, регистр приводится к верхнему — потом валидация.
///
/// Зачем валидировать на клиенте, если сервер всё равно проверит:
/// - friend_code интерполируется в path запроса (`/friends/<code>`, `/avatars/<code>`).
///   Без проверки можно подсунуть `..` / `/` / `?` и попасть в неожиданный endpoint
///   с тем же Bearer-токеном.
/// - Поведение `URL.append(path:)` в плане эскейпа метасимволов исторически нестабильно.
///   Лучше отбить мусор до отправки запроса.
enum FriendCode {
    /// Убирает дефисы/пробелы, переводит в верхний регистр. Не валидирует.
    static func normalize(_ raw: String) -> String {
        return raw
            .uppercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Нормализует ввод и проверяет формат `^[A-Z0-9]{10}$`.
    /// При невалидном коде бросает `AiuseAPIError.invalidFriendCode`.
    static func validated(_ raw: String) throws -> String {
        let normalized = normalize(raw)
        guard normalized.count == 10 else {
            throw AiuseAPIError.invalidFriendCode(raw)
        }
        for scalar in normalized.unicodeScalars {
            let isUpperLetter = (0x41...0x5A).contains(Int(scalar.value))   // A-Z
            let isDigit = (0x30...0x39).contains(Int(scalar.value))         // 0-9
            guard isUpperLetter || isDigit else {
                throw AiuseAPIError.invalidFriendCode(raw)
            }
        }
        return normalized
    }

    /// Форматирует код для показа: `XK7P3M9Q2A` → `XK7P-3M9Q-2A` (группы 4-4-2).
    /// Длину, отличную от канонических 10 символов, возвращает без изменений.
    static func formatted(_ raw: String) -> String {
        guard raw.count == 10 else { return raw }
        let i1 = raw.index(raw.startIndex, offsetBy: 4)
        let i2 = raw.index(raw.startIndex, offsetBy: 8)
        return "\(raw[..<i1])-\(raw[i1..<i2])-\(raw[i2...])"
    }
}
