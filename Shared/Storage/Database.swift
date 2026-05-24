import Foundation
import GRDB
import os.log

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
            // Paths содержат NSUserName → .private (личная инфа, не нужна в системных логах).
            AppLogger.db.info("Migrated DB from \(legacyURL.path, privacy: .private) to \(targetURL.path, privacy: .private)")
        } catch {
            AppLogger.db.error("Legacy DB migration failed: \(error.localizedDescription, privacy: .private)")
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
        migrator.registerMigration("v5_aiuse_tables") { db in
            // Свой профиль для aiuse — singleton (id всегда = 1).
            try db.execute(sql: """
                CREATE TABLE my_profile (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    friend_code TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    avatar_path TEXT,
                    sharing_enabled INTEGER NOT NULL DEFAULT 1,
                    server_user_id INTEGER NOT NULL
                )
            """)

            // Очередь snapshot'ов для отправки на сервер. hour_bucket = unix seconds.
            try db.execute(sql: """
                CREATE TABLE pending_snapshots (
                    hour_bucket INTEGER PRIMARY KEY,
                    tokens_input INTEGER NOT NULL,
                    tokens_output INTEGER NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT
                )
            """)
        }
        migrator.registerMigration("v6_input_tokens_no_cache") { db in
            // Колонка с чистым "input без кэша" — нужна aiuse-лидерборду
            // (input_tokens хранит с кэшем для cost-расчётов, его не меняем).
            try db.execute(sql: "ALTER TABLE ai_usage ADD COLUMN input_tokens_no_cache INTEGER NOT NULL DEFAULT 0")
            try db.execute(sql: "ALTER TABLE ai_usage_model ADD COLUMN input_tokens_no_cache INTEGER NOT NULL DEFAULT 0")
        }
        migrator.registerMigration("v7_aiuse_friend_cache") { db in
            // Кэш профилей друзей — для отображения имени/аватарки в UI и виджете
            // без сетевого запроса. Обновляется FriendsPullSyncer'ом.
            try db.execute(sql: """
                CREATE TABLE friend_profiles (
                    friend_code TEXT PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    sharing_enabled INTEGER NOT NULL DEFAULT 1,
                    avatar_blob BLOB,
                    avatar_mime TEXT,
                    avatar_etag TEXT,
                    last_fetched_at REAL NOT NULL
                )
            """)

            // Кэш лидерборда — для оффлайн-фолбэка и быстрого рендера.
            // payload_json содержит JSON-encoded LeaderboardResponse.
            try db.execute(sql: """
                CREATE TABLE leaderboard_cache (
                    period TEXT PRIMARY KEY,
                    fetched_at REAL NOT NULL,
                    payload_json TEXT NOT NULL
                )
            """)
        }
        migrator.registerMigration("v8_my_profile_avatar_blob") { db in
            // Свой аватар хранится локально как BLOB по аналогии с friend_profiles —
            // чтобы рендерить в UI без сетевого запроса и кэшировать через ETag.
            // avatar_path оставляем как legacy-колонку (никогда не использовалась).
            try db.execute(sql: "ALTER TABLE my_profile ADD COLUMN avatar_blob BLOB")
            try db.execute(sql: "ALTER TABLE my_profile ADD COLUMN avatar_mime TEXT")
            try db.execute(sql: "ALTER TABLE my_profile ADD COLUMN avatar_etag TEXT")
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
