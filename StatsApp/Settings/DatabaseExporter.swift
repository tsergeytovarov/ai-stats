import Foundation
import AppKit
import GRDB

enum DatabaseExporter {
    static func runExport(pool: DatabasePool, parentWindow: NSWindow?) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "ai-stats-\(DateUtils.isoDayCompact(Date())).db"

        let response: NSApplication.ModalResponse
        if let window = parentWindow {
            response = await panel.beginSheetModalForWindowAsync(window)
        } else {
            response = panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return }

        do {
            try await pool.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: Paths.databaseURL, to: url)
        } catch {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("alert.export_failed.title", comment: "")
                alert.informativeText = "\(error)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

extension NSSavePanel {
    @MainActor
    func beginSheetModalForWindowAsync(_ window: NSWindow) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            self.beginSheetModal(for: window) { cont.resume(returning: $0) }
        }
    }
}
