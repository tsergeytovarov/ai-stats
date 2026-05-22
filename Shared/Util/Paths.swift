import Foundation

enum Paths {
    static let appGroupID = "group.com.sergeytovarov.aistats"

    static var appSupportDir: URL {
        // Legacy location — used only for one-time migration.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ai-stats", isDirectory: true)
    }

    static var groupContainerDir: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            // Fallback for development / unsigned builds.
            let dir = appSupportDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var databaseURL: URL {
        groupContainerDir.appendingPathComponent("stats.db")
    }

    // Конфиг остаётся в ~/.config/ai-stats/ (виджету конфиг не нужен напрямую)
    static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/ai-stats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL {
        configDir.appendingPathComponent("config.json")
    }
}
