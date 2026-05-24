import SwiftUI
import AppKit

@main
struct StatsAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() } // обязателен какой-то Scene, видимое окно даст StatusItemController
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: AppContainer?
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let container = try AppContainer()
            self.container = container

            container.showFirstLaunchAlertIfNeeded()

            self.statusController = StatusItemController(
                viewModel: container.dropdownViewModel,
                onRefresh: { [weak self] in
                    guard let c = self?.container else { return }
                    Task { @MainActor in
                        let sources = c.buildFetchers()
                        for (name, fetchers) in sources {
                            try? await c.syncCoordinator.runOnce(source: name, fetchers: fetchers)
                        }
                        await c.dropdownViewModel.reload()
                    }
                },
                onOpenSettings: { [weak self] in self?.openSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
            statusController?.install()

            Task { @MainActor in await container.start() }
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("app.failed_to_start.title", comment: "")
            alert.informativeText = "\(error)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    @MainActor private func openSettings() {
        guard let container else { return }
        if settingsController == nil {
            settingsController = SettingsWindowController(container: container)
        }
        settingsController?.show()
    }
}
