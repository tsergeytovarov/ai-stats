import XCTest
@testable import StatsApp

@MainActor
final class GithubTokenMigrationTests: XCTestCase {
    private var configURL: URL!
    private var keychain: MemoryKeychainStore!
    private var secretsStore: SecretsStore!

    override func setUp() async throws {
        try await super.setUp()
        configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-stats-cfg-\(UUID().uuidString).json")
        keychain = MemoryKeychainStore()
        secretsStore = SecretsStore(keychain: keychain)
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

    private func loadConfigGithubToken() throws -> String {
        let cfg = try Config.decode(from: Data(contentsOf: configURL))
        return cfg.githubToken
    }

    func test_migrates_token_into_empty_combined() throws {
        try writeConfig(token: "ghp_AAA")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))
        let current = secretsStore.loadAll()

        let result = AppContainer.migrateGithubTokenFromConfig(
            config: cfg, secretsStore: secretsStore,
            currentSecrets: current, configURL: configURL
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.githubPAT, "ghp_AAA")
        XCTAssertEqual(secretsStore.loadAll().githubPAT, "ghp_AAA", "должно реально лежать в combined")
        XCTAssertEqual(try loadConfigGithubToken(), "", "поле в конфиге зачищено")
    }

    func test_noop_when_config_token_empty() throws {
        try writeConfig(token: "")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))
        let current = secretsStore.loadAll()

        let result = AppContainer.migrateGithubTokenFromConfig(
            config: cfg, secretsStore: secretsStore,
            currentSecrets: current, configURL: configURL
        )

        XCTAssertNil(result)
        XCTAssertNil(secretsStore.loadAll().githubPAT)
    }

    func test_combined_wins_when_both_have_value() throws {
        try secretsStore.setGithub("ghp_COMBINED")
        try writeConfig(token: "ghp_CONFIG_NEWER")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))
        let current = secretsStore.loadAll()

        _ = AppContainer.migrateGithubTokenFromConfig(
            config: cfg, secretsStore: secretsStore,
            currentSecrets: current, configURL: configURL
        )

        // Combined не должен быть перезаписан, но конфиг всё равно чистим (plaintext).
        XCTAssertEqual(secretsStore.loadAll().githubPAT, "ghp_COMBINED",
                       "combined не должен быть перезаписан если там что-то есть")
        XCTAssertEqual(try loadConfigGithubToken(), "", "plaintext всё равно зачищен")
    }

    func test_trims_whitespace_before_migration() throws {
        try writeConfig(token: "  ghp_TRIMMED  \n")
        let cfg = try Config.decode(from: Data(contentsOf: configURL))
        let current = secretsStore.loadAll()

        _ = AppContainer.migrateGithubTokenFromConfig(
            config: cfg, secretsStore: secretsStore,
            currentSecrets: current, configURL: configURL
        )

        XCTAssertEqual(secretsStore.loadAll().githubPAT, "ghp_TRIMMED")
    }

    func test_idempotent_on_second_call() throws {
        try writeConfig(token: "ghp_AAA")
        let cfg1 = try Config.decode(from: Data(contentsOf: configURL))
        _ = AppContainer.migrateGithubTokenFromConfig(
            config: cfg1, secretsStore: secretsStore,
            currentSecrets: secretsStore.loadAll(), configURL: configURL
        )

        let cfg2 = try Config.decode(from: Data(contentsOf: configURL))
        let result = AppContainer.migrateGithubTokenFromConfig(
            config: cfg2, secretsStore: secretsStore,
            currentSecrets: secretsStore.loadAll(), configURL: configURL
        )

        XCTAssertNil(result, "после первой миграции конфиг пустой → вторая итерация = noop")
        XCTAssertEqual(secretsStore.loadAll().githubPAT, "ghp_AAA")
    }
}
