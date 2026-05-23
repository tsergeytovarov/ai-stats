import Foundation
import Security

/// Чтение/запись секретов в Keychain. Тестируется через `MemoryKeychainStore`.
protocol KeychainStore {
    func get(account: String, service: String) -> String?
    func set(_ value: String, account: String, service: String) throws
    func delete(account: String, service: String) throws
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// Production-реализация через Security framework.
final class MacOSKeychainStore: KeychainStore {
    func get(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func set(_ value: String, account: String, service: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        // Сначала пробуем update; если нет — add.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// In-memory реализация для тестов.
final class MemoryKeychainStore: KeychainStore {
    private var storage: [String: String] = [:]

    private func key(_ account: String, _ service: String) -> String {
        "\(service)/\(account)"
    }

    func get(account: String, service: String) -> String? {
        storage[key(account, service)]
    }

    func set(_ value: String, account: String, service: String) throws {
        storage[key(account, service)] = value
    }

    func delete(account: String, service: String) throws {
        storage.removeValue(forKey: key(account, service))
    }
}

/// Константы для aiuse — где лежит api_secret.
enum AiuseKeychain {
    static let service = "tech.popovs.aiuse"
    static let account = "aiuse-api-secret"
}

/// Memory-кэш api_secret. Заполняется один раз при старте AppContainer
/// (из Keychain — это вызовет один macOS prompt), дальше живёт в памяти
/// процесса. AccountTabViewModel обновляет value после create/delete.
/// Нужен потому что unsigned-app триггерит Keychain-prompt на каждый
/// SecItemCopyMatching — без кэша это означает prompt каждые 5 минут.
@MainActor
final class SecretBox {
    var value: String?
}
