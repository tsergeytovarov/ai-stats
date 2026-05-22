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

    init() throws {
        let (cfg, wasCreated) = try ConfigLoader.loadOrCreate()
        self.config = cfg
        self.configWasCreated = wasCreated
        self.dbPool = try Database.openPool()
        let coordinator = SyncCoordinator(db: dbPool)
        self.syncCoordinator = coordinator
        self.dropdownViewModel = DropdownViewModel(db: dbPool, syncCoordinator: coordinator)
    }

    func buildFetchers() -> [(name: String, fetchers: [any Fetcher])] {
        var sources: [(String, [any Fetcher])] = []
        let ccFetchers: [any Fetcher] = config.enabledProviders.map { provider in
            CcusageFetcher(commandPrefix: config.ccusageCommand, provider: provider)
        }
        sources.append(("ccusage", ccFetchers))
        if config.githubEnabled {
            sources.append(("github", [GitHubFetcher(token: config.githubToken, login: config.githubLogin)]))
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
        alert.messageText = "Config initialized"
        alert.informativeText = "A default config was created at \(Paths.configURL.path). Add your GitHub token (optional) and restart the app. AI usage tracking already works."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Config")
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(Paths.configURL)
        }
    }
}
