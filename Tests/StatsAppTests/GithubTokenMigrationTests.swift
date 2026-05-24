import XCTest
@testable import StatsApp

@MainActor
final class GithubTokenMigrationTests: XCTestCase {
    private var configURL: URL!
    private var keychain: MemoryKeychainStore!

    override func setUp() async throws {
        try await super.setUp()
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-stats-cfg-\(UUID().uuidString).json")
        keychain = MemoryKeychainStore()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: configURL)
        try await super.tearDown()
    }

    private func writeConfig(token: String) throws {
        let payload: [String: Any] = [
            "github_token": token,
            "github_login": "popovs"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: configURL)
    }

    private func loadToken() -> String? {
        keychain.get(account: GithubKeychain.account, service: GithubKeychain.service)
    }

    private func loadConfigGithubToken() throws -> String {
        let cfg = try Config.decode(from: Data(contentsOf: configURL))
        return cfg.githubToken
    }

    func test_migrates_token_into_empty_keychain() throws {
        try writeConfig(token: "ghp_AAA")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))

        let migrated = AppContainer.migrateGithubTokenIfNeeded(
            config: cfg, keychain: keychain, configURL: configURL
        )

        XCTAssertTrue(migrated)
        XCTAssertEqual(loadToken(), "ghp_AAA")
        XCTAssertEqual(try loadConfigGithubToken(), "", "поле в конфиге зачищено")
    }

    func test_noop_when_config_token_empty() throws {
        try writeConfig(token: "")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))

        let migrated = AppContainer.migrateGithubTokenIfNeeded(
            config: cfg, keychain: keychain, configURL: configURL
        )

        XCTAssertFalse(migrated)
        XCTAssertNil(loadToken(), "ничего не должно появиться в Keychain")
    }

    func test_keychain_wins_when_both_have_value() throws {
        try keychain.set("ghp_KEYCHAIN", account: GithubKeychain.account, service: GithubKeychain.service)
        try writeConfig(token: "ghp_CONFIG_NEWER")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))

        _ = AppContainer.migrateGithubTokenIfNeeded(
            config: cfg, keychain: keychain, configURL: configURL
        )

        // Keychain не перезаписан, а поле в конфиге зачищено в любом случае
        // (если пользователь хочет переписать токен — пусть сначала удалит через Keychain Access).
        XCTAssertEqual(loadToken(), "ghp_KEYCHAIN", "Keychain не должен быть перезаписан")
        XCTAssertEqual(try loadConfigGithubToken(), "", "поле в конфиге всё равно зачищено — иначе plaintext остаётся на диске")
    }

    func test_trims_whitespace_before_migration() throws {
        try writeConfig(token: "  ghp_TRIMMED  \n")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))

        _ = AppContainer.migrateGithubTokenIfNeeded(
            config: cfg, keychain: keychain, configURL: configURL
        )

        XCTAssertEqual(loadToken(), "ghp_TRIMMED")
    }

    func test_idempotent_on_second_call() throws {
        try writeConfig(token: "ghp_AAA")
        let cfg1 = try Config.decode(from: Data(contentsOf: configURL))
        _ = AppContainer.migrateGithubTokenIfNeeded(
            config: cfg1, keychain: keychain, configURL: configURL
        )

        let cfg2 = try Config.decode(from: Data(contentsOf: configURL))
        let migrated = AppContainer.migrateGithubTokenIfNeeded(
            config: cfg2, keychain: keychain, configURL: configURL
        )

        XCTAssertFalse(migrated, "после первой миграции конфиг пустой → вторая итерация = noop")
        XCTAssertEqual(loadToken(), "ghp_AAA")
    }
}
