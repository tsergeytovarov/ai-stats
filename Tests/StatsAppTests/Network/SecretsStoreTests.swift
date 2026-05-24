import XCTest
@testable import StatsApp

final class SecretsStoreTests: XCTestCase {
    private var keychain: MemoryKeychainStore!
    private var store: SecretsStore!

    override func setUp() {
        super.setUp()
        keychain = MemoryKeychainStore()
        store = SecretsStore(keychain: keychain)
    }

    // MARK: - loadAll

    func test_loadAll_returnsEmpty_whenKeychainHasNothing() {
        let secrets = store.loadAll()
        XCTAssertNil(secrets.aiuseSecret)
        XCTAssertNil(secrets.githubPAT)
        XCTAssertFalse(secrets.hasAny)
    }

    func test_loadAll_returnsCombined_whenCombinedExists() throws {
        try keychain.set(
            #"{"aiuseSecret":"deadbeef","githubPAT":"ghp_abc"}"#,
            account: SecretsStore.combinedAccount,
            service: SecretsStore.combinedService
        )

        let secrets = store.loadAll()
        XCTAssertEqual(secrets.aiuseSecret, "deadbeef")
        XCTAssertEqual(secrets.githubPAT, "ghp_abc")
    }

    func test_loadAll_handlesPartialCombined_withOnlyAiuse() throws {
        try keychain.set(
            #"{"aiuseSecret":"deadbeef"}"#,
            account: SecretsStore.combinedAccount,
            service: SecretsStore.combinedService
        )

        let secrets = store.loadAll()
        XCTAssertEqual(secrets.aiuseSecret, "deadbeef")
        XCTAssertNil(secrets.githubPAT)
    }

    // MARK: - legacy migration

    func test_loadAll_migratesFromLegacy_whenCombinedMissing() throws {
        // Setup: оба legacy item'а есть, combined нет.
        try keychain.set("legacy-aiuse", account: AiuseKeychain.account, service: AiuseKeychain.service)
        try keychain.set("legacy-github", account: GithubKeychain.account, service: GithubKeychain.service)

        let secrets = store.loadAll()
        XCTAssertEqual(secrets.aiuseSecret, "legacy-aiuse")
        XCTAssertEqual(secrets.githubPAT, "legacy-github")

        // Combined item должен быть записан.
        let combined = keychain.get(account: SecretsStore.combinedAccount, service: SecretsStore.combinedService)
        XCTAssertNotNil(combined, "combined item должен быть создан при миграции")

        // Legacy items НЕ удаляются — orphan'ятся.
        XCTAssertEqual(keychain.get(account: AiuseKeychain.account, service: AiuseKeychain.service), "legacy-aiuse")
        XCTAssertEqual(keychain.get(account: GithubKeychain.account, service: GithubKeychain.service), "legacy-github")
    }

    func test_loadAll_migratesPartialLegacy_onlyAiusePresent() throws {
        try keychain.set("only-aiuse", account: AiuseKeychain.account, service: AiuseKeychain.service)
        // github legacy отсутствует

        let secrets = store.loadAll()
        XCTAssertEqual(secrets.aiuseSecret, "only-aiuse")
        XCTAssertNil(secrets.githubPAT)
    }

    func test_loadAll_skipsMigration_whenAllLegacyEmpty() {
        // Никаких legacy items, никаких combined.
        let secrets = store.loadAll()
        XCTAssertFalse(secrets.hasAny)
        // Combined НЕ создан — нет смысла писать пустой item.
        XCTAssertNil(keychain.get(account: SecretsStore.combinedAccount, service: SecretsStore.combinedService))
    }

    func test_loadAll_combinedWinsOverLegacy_whenBothExist() throws {
        try keychain.set(
            #"{"aiuseSecret":"new-aiuse","githubPAT":"new-github"}"#,
            account: SecretsStore.combinedAccount,
            service: SecretsStore.combinedService
        )
        try keychain.set("legacy-aiuse-OLD", account: AiuseKeychain.account, service: AiuseKeychain.service)
        try keychain.set("legacy-github-OLD", account: GithubKeychain.account, service: GithubKeychain.service)

        let secrets = store.loadAll()
        // Combined wins — legacy items не должны быть прочитаны (и тем более не должны побеждать).
        XCTAssertEqual(secrets.aiuseSecret, "new-aiuse")
        XCTAssertEqual(secrets.githubPAT, "new-github")
    }

    // MARK: - set + save

    func test_setAiuse_createsCombined_whenNoneExists() throws {
        try store.setAiuse("fresh-aiuse")

        let reloaded = store.loadAll()
        XCTAssertEqual(reloaded.aiuseSecret, "fresh-aiuse")
        XCTAssertNil(reloaded.githubPAT)
    }

    func test_setGithub_preservesAiuse() throws {
        try store.setAiuse("existing-aiuse")
        try store.setGithub("ghp_new")

        let reloaded = store.loadAll()
        XCTAssertEqual(reloaded.aiuseSecret, "existing-aiuse", "github update не должен затронуть aiuse")
        XCTAssertEqual(reloaded.githubPAT, "ghp_new")
    }

    func test_setAiuse_nilRemovesAiuse_keepsGithub() throws {
        try store.setAiuse("temp-aiuse")
        try store.setGithub("ghp_keep")

        try store.setAiuse(String?.none)

        let reloaded = store.loadAll()
        XCTAssertNil(reloaded.aiuseSecret)
        XCTAssertEqual(reloaded.githubPAT, "ghp_keep", "github не должен удалиться вместе с aiuse")
    }

    // MARK: - saveAll

    func test_saveAll_writesWithoutReadingFirst() throws {
        // saveAll должен писать переданный snapshot, не делая loadAll().
        // Тест опосредованный: записываем напрямую и читаем — должно совпасть.
        try store.saveAll(SecretsStore.Secrets(aiuseSecret: "x", githubPAT: "y"))

        let reloaded = store.loadAll()
        XCTAssertEqual(reloaded.aiuseSecret, "x")
        XCTAssertEqual(reloaded.githubPAT, "y")
    }

    // MARK: - idempotency

    func test_loadAll_isIdempotent_afterMigration() throws {
        try keychain.set("a", account: AiuseKeychain.account, service: AiuseKeychain.service)
        try keychain.set("g", account: GithubKeychain.account, service: GithubKeychain.service)

        let first = store.loadAll()
        let second = store.loadAll()
        XCTAssertEqual(first, second)
    }
}
