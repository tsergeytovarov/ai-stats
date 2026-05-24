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

        // Валидация ДО показа confirm-диалога — если файл невалидный, не пугаем
        // пользователя "сейчас всё перезапишу", а сразу показываем что не так.
        do {
            try DatabaseValidator.validate(at: importedURL)
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.import_failed.title", comment: "")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }

        let confirm = NSAlert()
        confirm.messageText = NSLocalizedString("alert.import.title", comment: "")
        let backupURL = backupURL()
        confirm.informativeText = String(format: NSLocalizedString("alert.import.body %@", comment: ""), backupURL.path)
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: NSLocalizedString("alert.import.replace", comment: ""))
        confirm.addButton(withTitle: NSLocalizedString("alert.import.cancel", comment: ""))
        guard confirm.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try Database.checkpointAndClose(currentPool)

            // 1. Backup ДО любых деструктивных операций.
            let backupExists: Bool
            if FileManager.default.fileExists(atPath: Paths.databaseURL.path) {
                try FileManager.default.copyItem(at: Paths.databaseURL, to: backupURL)
                backupExists = true
            } else {
                backupExists = false
            }

            // 2. Удалим WAL/SHM/original — нужно чтобы copyItem не наткнулся на existing.
            for suffix in ["", "-wal", "-shm"] {
                let url = URL(fileURLWithPath: Paths.databaseURL.path + suffix)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            // 3. Copy с rollback на failure: если что-то пошло не так на этом этапе,
            // восстанавливаем оригинал из backup'а, чтобы юзер не остался без БД.
            do {
                try FileManager.default.copyItem(at: importedURL, to: Paths.databaseURL)
            } catch {
                if backupExists {
                    try? FileManager.default.copyItem(at: backupURL, to: Paths.databaseURL)
                }
                throw error
            }
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.import_failed.title", comment: "")
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
