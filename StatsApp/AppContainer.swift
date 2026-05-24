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

        // Один Keychain prompt при старте — дальше отдаём из memory cache.
        // Без этого macOS триггерит prompt на каждый sync-запрос (unsigned-app).
        let box = SecretBox()
        box.value = kc.get(account: AiuseKeychain.account, service: AiuseKeychain.service)
        self.secretBox = box

        // GitHub PAT: с v0.2.1 живёт в Keychain. Один раз мигрируем из config.json
        // если пользователь только что вставил туда токен (или обновился со старой версии).
        let ghBox = GithubTokenBox()
        Self.migrateGithubTokenIfNeeded(config: cfg, keychain: kc)
        ghBox.value = kc.get(account: GithubKeychain.account, service: GithubKeychain.service) ?? ""
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

        let coordinator = SyncCoordinator(
            db: dbPool,
            snapshotSyncer: syncer,
            friendsPullSyncer: friendsPull,
            leaderboardPullSyncer: lbPull
        )
        self.syncCoordinator = coordinator
        let dbPoolRef = dbPool
        // githubEnabled теперь определяется runtime-токеном (из Keychain), а не полем конфига.
        let githubEnabledNow = !ghBox.value.isEmpty && !cfg.githubLogin.isEmpty
        self.dropdownViewModel = DropdownViewModel(
            db: dbPool,
            syncCoordinator: coordinator,
            api: api,
            hasAccount: { (try? dbPoolRef.read { try StatsQueries.loadMyProfile($0) }) ?? nil != nil },
            githubEnabled: githubEnabledNow
        )
    }

    /// Однократная миграция github_token из config.json в Keychain.
    /// Идемпотентна: если токен в конфиге пуст — ничего не делает; если Keychain уже заполнен
    /// и в конфиге тоже что-то лежит — Keychain побеждает, поле в конфиге зануляется.
    @discardableResult
    nonisolated static func migrateGithubTokenIfNeeded(
        config: Config,
        keychain: KeychainStore,
        configURL: URL = Paths.configURL
    ) -> Bool {
        let configToken = config.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configToken.isEmpty else { return false }

        let existing = keychain.get(account: GithubKeychain.account, service: GithubKeychain.service)
        if existing == nil || existing?.isEmpty == true {
            // Keychain пустой — переливаем туда то что было в конфиге.
            try? keychain.set(
                configToken,
                account: GithubKeychain.account,
                service: GithubKeychain.service
            )
        }
        // В любом случае: зануляем поле в конфиге, чтобы plaintext-токен не оставался на диске.
        try? ConfigLoader.clearGithubTokenField(at: configURL)
        return true
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
        AccountTabViewModel(api: aiuseAPI, keychain: keychain, secretBox: secretBox, db: dbPool)
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
