import Foundation
import AppKit
import GRDB

@MainActor
enum DatabaseImporter {
    /// Возвращает true если импорт прошёл; вызывающий должен переоткрыть pool.
    static func runImport(currentPool: DatabasePool, parentWindow: NSWindow?) async -> Bool {
        let open = NSOpenPanel()
        open.canChooseDirectories = false
        open.canChooseFiles = true
        open.allowsMultipleSelection = false
        let pickResponse: NSApplication.ModalResponse
        if let window = parentWindow {
            pickResponse = await open.beginSheetModalForWindowAsync(window)
        } else {
            pickResponse = open.runModal()
        }
        guard pickResponse == .OK, let importedURL = open.url else { return false }

        let confirm = NSAlert()
        confirm.messageText = "Replace database?"
        let backupURL = backupURL()
        confirm.informativeText = "Your current database will be backed up to:\n\(backupURL.path)\n\nContinue?"
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        guard confirm.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try Database.checkpointAndClose(currentPool)
            if FileManager.default.fileExists(atPath: Paths.databaseURL.path) {
                try FileManager.default.copyItem(at: Paths.databaseURL, to: backupURL)
            }
            // Удалим WAL/SHM если остались, чтобы не было mismatch с новым файлом.
            for suffix in ["", "-wal", "-shm"] {
                let url = URL(fileURLWithPath: Paths.databaseURL.path + suffix)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            try FileManager.default.copyItem(at: importedURL, to: Paths.databaseURL)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import failed"
            alert.informativeText = "\(error)"
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    private static func backupURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let suffix = formatter.string(from: Date())
        return Paths.appSupportDir.appendingPathComponent("stats.db.backup-\(suffix)")
    }
}

// NSOpenPanel inherits beginSheetModalForWindowAsync from the NSSavePanel extension in DatabaseExporter.swift
