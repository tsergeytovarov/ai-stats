import Foundation
import os.log

/// Объединяет все Keychain-секреты приложения (aiuse api_secret + GitHub PAT)
/// в один Keychain item с JSON-payload'ом. Зачем: каждый SecItemCopyMatching
/// триггерит ACL-prompt в unsigned-сборке. Раньше было 2 prompt'а на запуск
/// (aiuse + github), теперь — 1.
///
/// Миграция: при первом запуске после апдейта `loadAll()` пробует прочитать
/// combined-item. Если его нет — fallback на legacy раздельные items
/// (AiuseKeychain, GithubKeychain) → собрать в combined → записать.
/// Legacy items НЕ удаляются — удаление = ещё 2 prompt'а на миграционном
/// запуске. Они становятся orphan'ами и больше не читаются.
final class SecretsStore {
    /// Service / account для нового combined Keychain item.
    static let combinedService = "tech.popovs.aistats.secrets"
    static let combinedAccount = "combined-v1"

    /// Все секреты приложения. Любое поле может быть nil — это норма.
    struct Secrets: Codable, Equatable {
        var aiuseSecret: String?
        var githubPAT: String?
        var githubLogin: String?

        static let empty = Secrets(aiuseSecret: nil, githubPAT: nil, githubLogin: nil)

        /// true если есть хоть один непустой секрет (для решения нужна ли запись в combined).
        /// githubLogin сюда не входит — это не секрет, а лишь метаданные токена.
        var hasAny: Bool {
            (aiuseSecret?.isEmpty == false) || (githubPAT?.isEmpty == false)
        }
    }

    private let keychain: KeychainStore

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    /// Загружает все секреты. Делает максимум 1 Keychain hit в установившемся
    /// state'е (combined есть), или 2-3 hit'а на миграционном запуске
    /// (combined нет → читаем legacy + пишем combined).
    func loadAll() -> Secrets {
        // 1. Combined-first.
        if let json = keychain.get(account: Self.combinedAccount, service: Self.combinedService),
           let secrets = decode(json) {
            return secrets
        }

        // 2. Legacy migration. Читаем старые items, собираем в combined.
        let aiuse = keychain.get(account: AiuseKeychain.account, service: AiuseKeychain.service)
        let github = keychain.get(account: GithubKeychain.account, service: GithubKeychain.service)
        let migrated = Secrets(aiuseSecret: aiuse, githubPAT: github, githubLogin: nil)

        if migrated.hasAny {
            do {
                try save(migrated)
                AppLogger.aiuse.info("Migrated secrets to combined Keychain item")
            } catch {
                AppLogger.aiuse.error(
                    "Combined-secrets migration failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        return migrated
    }

    /// Обновляет aiuseSecret в combined-item, сохраняя githubPAT.
    /// nil → удалить aiuseSecret (но не сам combined-item).
    func setAiuse(_ value: String?) throws {
        var current = loadAll()
        current.aiuseSecret = value
        try save(current)
    }

    /// Обновляет githubPAT в combined-item, сохраняя aiuseSecret.
    func setGithub(_ value: String?) throws {
        var current = loadAll()
        current.githubPAT = value
        try save(current)
    }

    /// Пишет github-токен и логин одним апдейтом combined-item, сохраняя aiuseSecret.
    func setGithubAuth(token: String?, login: String?) throws {
        var current = loadAll()
        current.githubPAT = token
        current.githubLogin = login
        try save(current)
    }

    /// Прямой write полного набора, БЕЗ предварительного read. Caller отвечает
    /// за полноту переданного `secrets`. Нужно когда вызывающий уже имеет свежий
    /// snapshot и не хочет тратить лишний Keychain hit на повторный loadAll().
    func saveAll(_ secrets: Secrets) throws {
        try save(secrets)
    }

    // MARK: - private

    private func decode(_ json: String) -> Secrets? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Secrets.self, from: data)
    }

    private func save(_ secrets: Secrets) throws {
        let data = try JSONEncoder().encode(secrets)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try keychain.set(json, account: Self.combinedAccount, service: Self.combinedService)
    }
}
