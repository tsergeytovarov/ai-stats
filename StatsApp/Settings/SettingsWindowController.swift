import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let container: AppContainer
    private var window: NSWindow?

    init(container: AppContainer) { self.container = container }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(
            configPath: Paths.configURL.path,
            dbPath: Paths.databaseURL.path,
            dbSizeBytes: dbSize(),
            version: "0.2.0",
            onOpenConfig: { NSWorkspace.shared.open(Paths.configURL) },
            onExport: { [weak self] in self?.doExport() },
            onImport: { [weak self] in self?.doImport() },
            onRefreshNow: { [weak self] in self?.doRefresh() },
            accountViewModel: self.container.makeAccountTabViewModel(),
            friendsViewModel: self.container.makeFriendsTabViewModel(),
            blockedViewModel: self.container.makeBlockedTabViewModel()
        )
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Burn Settings"
        win.styleMask = [.titled, .closable]
        win.delegate = self
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func dbSize() -> Int64 {
        let attr = try? FileManager.default.attributesOfItem(atPath: Paths.databaseURL.path)
        return (attr?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func doExport() {
        Task { @MainActor in
            await DatabaseExporter.runExport(pool: container.dbPool, parentWindow: window)
        }
    }

    private func doImport() {
        Task { @MainActor in
            let imported = await DatabaseImporter.runImport(currentPool: container.dbPool, parentWindow: window)
            if imported {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("alert.import_success.title", comment: "")
                alert.informativeText = NSLocalizedString("alert.import_success.body", comment: "")
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }

    private func doRefresh() {
        Task { @MainActor in
            let sources = container.buildFetchers()
            for (name, fetchers) in sources {
                try? await container.syncCoordinator.runOnce(source: name, fetchers: fetchers)
            }
            await container.dropdownViewModel.reload()
        }
    }
}
