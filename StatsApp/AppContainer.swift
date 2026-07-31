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
    let githubLoginBox: GithubLoginBox
    let authService: AuthService
    let aiuseAPI: AiuseAPIClient

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

        let ghLoginBox = GithubLoginBox()
        // OAuth-логин (из combined-secrets) приоритетнее legacy config.github_login.
        ghLoginBox.value = secrets.githubLogin ?? cfg.githubLogin
        self.githubLoginBox = ghLoginBox

        // Жёстко требуем https для aiuse: иначе Bearer-токен из Keychain
        // утечёт plain-text'ом на любой http-эндпоинт из конфига.
        let baseURL = try Self.validateAiuseBaseURL(cfg.aiuseApiBaseURL)
        let api = AiuseAPIClient(
            baseURL: baseURL,
            secretProvider: { box.value }
        )
        self.aiuseAPI = api
        self.authService = AuthService(
            authBaseURL: baseURL,
            api: api,
            webAuth: ASWebAuthenticator()
        )

        // Ингестор аналитики читает ~/.claude и ~/.codex; SyncCoordinator дёргает
        // его с гейтом раз в час (спека 5.1).
        let ingestor = AnalyticsIngestor(dbWriter: dbPool)
        let coordinator = SyncCoordinator(
            db: dbPool,
            analyticsIngest: { try await ingestor.ingest() }
        )

        // Опрос лимитов — свой актор со своими расписаниями на провайдера
        // (Codex раз в 5 минут, OpenCode раз в 15, Claude раз в час с уважением
        // к Retry-After из 429). SyncCoordinator просто дёргает тик.
        // Репозиторий один на всё приложение: координатор им пишет, вью-модель
        // им же читает — второй инстанс тут не нужен.
        let limitsRepository = LimitsRepository(db: dbPool)
        let limitsCoordinator = LimitsCoordinator(
            fetchers: [CodexLimitsFetcher(), ClaudeLimitsFetcher(), OpenCodeLimitsFetcher()],
            repository: limitsRepository)
        coordinator.limitsTick = { await limitsCoordinator.tick() }

        self.syncCoordinator = coordinator
        self.dropdownViewModel = DropdownViewModel(
            db: dbPool,
            syncCoordinator: coordinator,
            limitsRepository: limitsRepository
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
        let vm = AccountTabViewModel(
            api: aiuseAPI,
            auth: authService,
            secretsStore: secretsStore,
            secretBox: secretBox,
            githubTokenBox: githubTokenBox,
            githubLoginBox: githubLoginBox,
            db: dbPool
        )
        vm.onSignedIn = { [weak self] in await self?.refreshSourcesAfterSignIn() }
        return vm
    }

    /// Пересобирает fetcher-источники и перезапускает периодический sync после OAuth.
    func refreshSourcesAfterSignIn() async {
        let sources = buildFetchers()
        let interval = TimeInterval(config.syncIntervalMinutes * 60)
        syncCoordinator.startTimer(interval: interval, sources: sources)
    }

    func buildFetchers() -> [(name: String, fetchers: [any Fetcher])] {
        var sources: [(String, [any Fetcher])] = []
        let ccFetchers: [any Fetcher] = config.enabledProviders.map { provider in
            CcusageFetcher(commandPrefix: config.ccusageCommand, provider: provider)
        }
        sources.append(("ccusage", ccFetchers))
        sources.append(("claude-cowork", [ClaudeCoworkFetcher()]))
        return sources
    }

    func start() async {
        let sources = buildFetchers()
        // Initial run, потом periodic
        for (name, fetchers) in sources {
            try? await syncCoordinator.runOnce(source: name, fetchers: fetchers)
        }
        // Ингест аналитики при старте — безусловно (force), чтобы смена версии
        // расчёта вердиктов подхватилась даже при перезапуске в пределах часа.
        await syncCoordinator.maybeRunAnalyticsIngest(force: true)
        // Лимиты — тоже сразу на старте, а не через 15 минут до первого тика
        // общего таймера синка (находка 3 финального ревью): первый tick()
        // координатора сам восстанавливает lastAttempt/retryAfter из БД раньше,
        // чем решает, кого опрашивать, так что ещё не истёкший 429 не долбится.
        await syncCoordinator.limitsTick?()
        let interval = TimeInterval(config.syncIntervalMinutes * 60)
        syncCoordinator.startTimer(interval: interval, sources: sources)
        await dropdownViewModel.reload()
        await dropdownViewModel.loadLimits()
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
