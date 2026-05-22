import Foundation
import GRDB

enum Database {
    static func openPool(at url: URL = Paths.databaseURL) throws -> DatabasePool {
        migrateLegacyLocationIfNeeded(targetURL: url)
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        try migrate(pool)
        return pool
    }

    private static func migrateLegacyLocationIfNeeded(targetURL: URL) {
        let fm = FileManager.default
        let legacyURL = Paths.appSupportDir.appendingPathComponent("stats.db")
        guard !fm.fileExists(atPath: targetURL.path),
              fm.fileExists(atPath: legacyURL.path) else { return }
        do {
            try? fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: legacyURL, to: targetURL)
            // Также пробуем перенести WAL/SHM
            for suffix in ["-wal", "-shm"] {
                let legacy = URL(fileURLWithPath: legacyURL.path + suffix)
                let target = URL(fileURLWithPath: targetURL.path + suffix)
                if fm.fileExists(atPath: legacy.path) {
                    try? fm.copyItem(at: legacy, to: target)
                }
            }
            NSLog("ai-stats: migrated DB from \(legacyURL.path) to \(targetURL.path)")
        } catch {
            NSLog("ai-stats: legacy DB migration failed: \(error)")
        }
    }

    static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE ai_usage (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    day TEXT NOT NULL,
                    source TEXT NOT NULL,
                    models_json TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    cost_usd REAL NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(day, source)
                )
            """)
            try db.execute(sql: "CREATE INDEX idx_ai_usage_day ON ai_usage(day)")

            try db.execute(sql: """
                CREATE TABLE github_activity (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    day TEXT NOT NULL,
                    repo TEXT NOT NULL,
                    commits INTEGER NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(day, repo)
                )
            """)
            try db.execute(sql: "CREATE INDEX idx_github_day ON github_activity(day)")

            try db.execute(sql: """
                CREATE TABLE sync_state (
                    source TEXT PRIMARY KEY,
                    last_sync_at TEXT NOT NULL,
                    last_error TEXT
                )
            """)
        }
        migrator.registerMigration("v2_add_github_loc") { db in
            try db.execute(sql: """
                CREATE TABLE github_loc_weekly (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    week_start TEXT NOT NULL,
                    repo TEXT NOT NULL,
                    additions INTEGER NOT NULL,
                    deletions INTEGER NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(week_start, repo)
                )
            """)
            try db.execute(sql: "CREATE INDEX idx_github_loc_week ON github_loc_weekly(week_start)")
        }
        migrator.registerMigration("v3_add_ai_usage_model") { db in
            try db.execute(sql: """
                CREATE TABLE ai_usage_model (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    day TEXT NOT NULL,
                    source TEXT NOT NULL,
                    model TEXT NOT NULL,
                    input_tokens INTEGER NOT NULL,
                    output_tokens INTEGER NOT NULL,
                    cost_usd REAL NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(day, source, model)
                )
            """)
            try db.execute(sql: "CREATE INDEX idx_ai_usage_model_day ON ai_usage_model(day)")
            try db.execute(sql: "CREATE INDEX idx_ai_usage_model_model ON ai_usage_model(model)")
        }
        migrator.registerMigration("v4_replace_loc_weekly_with_daily") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS github_loc_weekly")
            try db.execute(sql: """
                CREATE TABLE github_loc_daily (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    day TEXT NOT NULL,
                    repo TEXT NOT NULL,
                    additions INTEGER NOT NULL,
                    deletions INTEGER NOT NULL,
                    updated_at TEXT NOT NULL,
                    UNIQUE(day, repo)
                )
            """)
            try db.execute(sql: "CREATE INDEX idx_github_loc_daily_day ON github_loc_daily(day)")
        }
        try migrator.migrate(writer)
    }

    /// Закрывает write+read connections. После этого pool использовать нельзя.
    static func checkpointAndClose(_ pool: DatabasePool) throws {
        try pool.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
        try pool.close()
    }
}
