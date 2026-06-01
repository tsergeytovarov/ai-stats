import Foundation
import AppKit
import GRDB

@MainActor
final class AppContainer {
    let config: Config
    let configWasCreated: Bool
    let dbPool: DatabasePool
    let syncCoordinator: SyncCoordinator
    let dropdownViewModel: DropdownViewModel
    let keychain: KeychainStore
    let secretsStore: SecretsStore
    let secretBox: SecretBox
    let githubTokenBox: GithubTokenBox
    let aiuseAPI: AiuseAPIClient
    let snapshotSyncer: SnapshotSyncer
    let friendsPullSyncer: FriendsPullSyncer
    let leaderboardPullSyncer: LeaderboardPullSyncer

    init() throws {
        let (cfg, wasCreated) = try ConfigLoader.loadOrCreate()
        self.config = cfg
        self.configWasCreated = wasCreated
        self.dbPool = try Database.openPool()

        // aiuse wiring
        let kc = MacOSKeychainStore()
        self.keychain = kc

        // Все секреты — aiuse api_secret + GitHub PAT — в одном Keychain item'е.
        // Раньше было 2 prompt'а на запуск (по одному на item), теперь 1.
        // SecretsStore.loadAll() автоматически мигрирует с legacy AiuseKeychain /
        // GithubKeychain items в combined при первом запуске — после этого
        // combined существует и подтягивается одним hit'ом.
        let store = SecretsStore(keychain: kc)
        self.secretsStore = store
        var secrets = store.loadAll()

        // Миграция github_token из config.json. Делаем INPLACE в локальный snapshot
        // и одним write'ом через saveAll — иначе бы здесь были лишние reads.
        if let updated = Self.migrateGithubTokenFromConfig(
            config: cfg, secretsStore: store, currentSecrets: secrets
        ) {
            secrets = updated
        }

        // Memory caches (SecretBox/GithubTokenBox) остаются — после loadAll()
        // мы не дёргаем Keychain до конца сессии.
        let box = SecretBox()
        box.value = secrets.aiuseSecret
        self.secretBox = box

        let ghBox = GithubTokenBox()
        ghBox.value = secrets.githubPAT ?? ""
        self.githubTokenBox = ghBox

        // Жёстко требуем https для aiuse: иначе Bearer-токен из Keychain
        // утечёт plain-text'ом на любой http-эндпоинт из конфига.
        let baseURL = try Self.validateAiuseBaseURL(cfg.aiuseApiBaseURL)
        let api = AiuseAPIClient(
            baseURL: baseURL,
            secretProvider: { box.value }
        )
        self.aiuseAPI = api
        let syncer = SnapshotSyncer(db: dbPool, api: api)
        self.snapshotSyncer = syncer

        let dbPoolRefForSyncers = dbPool
        let hasAccountCheck: () -> Bool = {
            (try? dbPoolRefForSyncers.read { try StatsQueries.loadMyProfile($0) }) ?? nil != nil
        }
        let friendsPull = FriendsPullSyncer(db: dbPool, api: api, hasAccount: hasAccountCheck)
        let lbPull = LeaderboardPullSyncer(db: dbPool, api: api, hasAccount: hasAccountCheck)
        self.friendsPullSyncer = friendsPull
        self.leaderboardPullSyncer = lbPull

        // demo_mode=true → передаём nil syncers в координатор, чтобы он не дёргал
        // aiuse-сервер и не затирал seed-данные leaderboard'а. Сами FriendsPullSyncer/
        // LeaderboardPullSyncer/SnapshotSyncer существуют в container'е (через них
        // ViewModel может make-call'ы по запросу пользователя), но из автоматического
        // sync-тика они исключены.
        let coordinator: SyncCoordinator
        if cfg.demoMode {
            AppLogger.sync.info("demo_mode=true — aiuse syncs отключены (snapshot/friends/leaderboard)")
            coordinator = SyncCoordinator(
                db: dbPool,
                snapshotSyncer: nil,
                friendsPullSyncer: nil,
                leaderboardPullSyncer: nil
            )
        } else {
            coordinator = SyncCoordinator(
                db: dbPool,
                snapshotSyncer: syncer,
                friendsPullSyncer: friendsPull,
                leaderboardPullSyncer: lbPull
            )
        }
        self.syncCoordinator = coordinator
        let dbPoolRef = dbPool
        // githubEnabled теперь определяется runtime-токеном (из Keychain), а не полем конфига.
        let githubEnabledNow = !ghBox.value.isEmpty && !cfg.githubLogin.isEmpty
        self.dropdownViewModel = DropdownViewModel(
            db: dbPool,
            syncCoordinator: coordinator,
            api: api,
            hasAccount: { (try? dbPoolRef.read { try StatsQueries.loadMyProfile($0) }) ?? nil != nil },
            githubEnabled: githubEnabledNow,
            demoMode: cfg.demoMode
        )
    }

    /// Миграция github_token из config.json в combined Keychain item.
    /// Возвращает обновлённый snapshot если миграция произошла, nil если конфиг пустой
    /// (тогда caller продолжает использовать `currentSecrets` без изменений).
    ///
    /// Идемпотентна: если в combined уже есть githubPAT — Keychain wins, поле
    /// в конфиге всё равно зануляется (plaintext-токен не должен оставаться на диске).
    nonisolated static func migrateGithubTokenFromConfig(
        config: Config,
        secretsStore: SecretsStore,
        currentSecrets: SecretsStore.Secrets,
        configURL: URL = Paths.configURL
    ) -> SecretsStore.Secrets? {
        let configToken = config.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configToken.isEmpty else { return nil }

        var updated = currentSecrets
        let existing = updated.githubPAT ?? ""
        if existing.isEmpty {
            updated.githubPAT = configToken
            // saveAll НЕ читает Keychain до записи — мы передаём полный snapshot.
            try? secretsStore.saveAll(updated)
        }
        // В любом случае: зануляем поле в конфиге.
        try? ConfigLoader.clearGithubTokenField(at: configURL)
        return updated
    }

    /// Валидация aiuse_api_base_url: только https. Любая другая схема — ошибка.
    /// Сохранили fallback на дефолтный popovs.tech если конфиг вообще не разбирается как URL —
    /// но если разобрался и схема не https, бросаем явную ошибку, чтобы юзер увидел её в alert.
    nonisolated static func validateAiuseBaseURL(_ raw: String) throws -> URL {
        let defaultURL = URL(string: "https://aiuse.popovs.tech/api")!
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultURL }
        guard let url = URL(string: trimmed) else { return defaultURL }
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw ConfigError.insecureBaseURL(scheme: url.scheme)
        }
        return url
    }

    /// Создаёт fresh AccountTabViewModel — для каждого открытия окна настроек.
    func makeAccountTabViewModel() -> AccountTabViewModel {
        AccountTabViewModel(api: aiuseAPI, secretsStore: secretsStore, secretBox: secretBox, db: dbPool)
    }

    /// Создаёт fresh FriendsTabViewModel — для каждого открытия окна настроек.
    func makeFriendsTabViewModel() -> FriendsTabViewModel {
        let dbPoolRef = dbPool
        return FriendsTabViewModel(
            api: aiuseAPI,
            db: dbPool,
            hasAccount: { (try? dbPoolRef.read { try StatsQueries.loadMyProfile($0) }) ?? nil != nil }
        )
    }

    /// Создаёт fresh BlockedTabViewModel.
    func makeBlockedTabViewModel() -> BlockedTabViewModel {
        let dbPoolRef = dbPool
        return BlockedTabViewModel(
            api: aiuseAPI,
            hasAccount: { (try? dbPoolRef.read { try StatsQueries.loadMyProfile($0) }) ?? nil != nil }
        )
    }

    func buildFetchers() -> [(name: String, fetchers: [any Fetcher])] {
        var sources: [(String, [any Fetcher])] = []
        let ccFetchers: [any Fetcher] = config.enabledProviders.map { provider in
            CcusageFetcher(commandPrefix: config.ccusageCommand, provider: provider)
        }
        sources.append(("ccusage", ccFetchers))
        sources.append(("claude-cowork", [ClaudeCoworkFetcher()]))
        // Токен берём из Keychain-бэкенного box'а, не из конфига.
        let token = githubTokenBox.value
        if !token.isEmpty && !config.githubLogin.isEmpty {
            sources.append(("github", [GitHubFetcher(token: token, login: config.githubLogin)]))
        }
        return sources
    }

    func start() async {
        let sources = buildFetchers()
        // Initial run, потом periodic
        for (name, fetchers) in sources {
            try? await syncCoordinator.runOnce(source: name, fetchers: fetchers)
        }
        let interval = TimeInterval(config.syncIntervalMinutes * 60)
        syncCoordinator.startTimer(interval: interval, sources: sources)
        await dropdownViewModel.reload()
    }

    func showFirstLaunchAlertIfNeeded() {
        guard configWasCreated else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.config_initialized.title", comment: "")
        alert.informativeText = String(format: NSLocalizedString("alert.config_initialized.body %@", comment: ""), Paths.configURL.path)
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("alert.config_initialized.open", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("alert.config_initialized.ok", comment: ""))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Paths.configURL)
        }
    }
}
