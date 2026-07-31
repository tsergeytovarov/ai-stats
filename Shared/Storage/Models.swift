import Foundation
import GRDB

struct AIUsageRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "ai_usage"

    var id: Int64?
    var day: String
    var source: String
    var modelsJson: String
    var inputTokens: Int64           // включает cache (для cost/UI)
    var inputTokensNoCache: Int64 = 0   // только без cache (для aiuse-лидерборда; default — existing rows)
    var outputTokens: Int64
    var costUsd: Double
    var updatedAt: String

    enum Columns {
        static let id = Column("id")
        static let day = Column("day")
        static let source = Column("source")
        static let modelsJson = Column("models_json")
        static let inputTokens = Column("input_tokens")
        static let inputTokensNoCache = Column("input_tokens_no_cache")
        static let outputTokens = Column("output_tokens")
        static let costUsd = Column("cost_usd")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case source
        case modelsJson = "models_json"
        case inputTokens = "input_tokens"
        case inputTokensNoCache = "input_tokens_no_cache"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
        case updatedAt = "updated_at"
    }
}

struct AIUsageModelRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "ai_usage_model"

    var id: Int64?
    var day: String
    var source: String
    var model: String
    var inputTokens: Int64           // включает cache (для cost/UI)
    var inputTokensNoCache: Int64 = 0   // только без cache (для aiuse-лидерборда; default — existing rows)
    var outputTokens: Int64
    var costUsd: Double
    var updatedAt: String

    enum Columns {
        static let id = Column("id")
        static let day = Column("day")
        static let source = Column("source")
        static let model = Column("model")
        static let inputTokens = Column("input_tokens")
        static let inputTokensNoCache = Column("input_tokens_no_cache")
        static let outputTokens = Column("output_tokens")
        static let costUsd = Column("cost_usd")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case source
        case model
        case inputTokens = "input_tokens"
        case inputTokensNoCache = "input_tokens_no_cache"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
        case updatedAt = "updated_at"
    }
}

struct SyncStateRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "sync_state"

    var source: String
    var lastSyncAt: String
    var lastError: String?

    enum Columns {
        static let source = Column("source")
        static let lastSyncAt = Column("last_sync_at")
        static let lastError = Column("last_error")
    }

    enum CodingKeys: String, CodingKey {
        case source
        case lastSyncAt = "last_sync_at"
        case lastError = "last_error"
    }
}

/// Свой профиль aiuse — singleton, всегда одна строка с id = 1.
struct MyProfileRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "my_profile"

    var id: Int64 = 1
    var friendCode: String
    var displayName: String
    var avatarPath: String?
    var sharingEnabled: Bool
    var serverUserId: Int64
    var avatarBlob: Data? = nil
    var avatarMime: String? = nil
    var avatarEtag: String? = nil

    enum Columns {
        static let id = Column("id")
        static let friendCode = Column("friend_code")
        static let displayName = Column("display_name")
        static let avatarPath = Column("avatar_path")
        static let sharingEnabled = Column("sharing_enabled")
        static let serverUserId = Column("server_user_id")
        static let avatarBlob = Column("avatar_blob")
        static let avatarMime = Column("avatar_mime")
        static let avatarEtag = Column("avatar_etag")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case friendCode = "friend_code"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case sharingEnabled = "sharing_enabled"
        case serverUserId = "server_user_id"
        case avatarBlob = "avatar_blob"
        case avatarMime = "avatar_mime"
        case avatarEtag = "avatar_etag"
    }
}

// MARK: - Analytics (миграция v9)

/// Один «ход» агента (Claude Code / Codex) — user-запрос + все ответы модели до
/// следующего запроса. Хранится вся история; окно 30 дней накладывается запросом.
/// `id: Int64?` — AUTOINCREMENT PK; upsert идёт по UNIQUE(source, session, ts).
struct AnalyticsTurnRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "analytics_turns"

    var id: Int64?
    var source: String
    var ts: String
    var day: String
    var session: String
    var project: String
    var model: String
    var effort: String = ""
    var origin: String
    var promptHead: String = ""
    var promptChars: Int64 = 0
    var nRequests: Int64 = 0
    var nToolCalls: Int64 = 0
    var nEdits: Int64 = 0
    var inputTokens: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheCreate5m: Int64 = 0
    var cacheCreate1h: Int64 = 0
    var outputTokens: Int64 = 0
    var costUsd: Double = 0
    var heurTier: Int?
    var cfModel: String?
    var cfUsd: Double?
    var expSavedUsd: Double = 0

    enum Columns {
        static let id = Column("id")
        static let source = Column("source")
        static let ts = Column("ts")
        static let day = Column("day")
        static let session = Column("session")
        static let project = Column("project")
        static let model = Column("model")
        static let effort = Column("effort")
        static let origin = Column("origin")
        static let promptHead = Column("prompt_head")
        static let promptChars = Column("prompt_chars")
        static let nRequests = Column("n_requests")
        static let nToolCalls = Column("n_tool_calls")
        static let nEdits = Column("n_edits")
        static let inputTokens = Column("input_tokens")
        static let cacheRead = Column("cache_read")
        static let cacheCreate5m = Column("cache_create_5m")
        static let cacheCreate1h = Column("cache_create_1h")
        static let outputTokens = Column("output_tokens")
        static let costUsd = Column("cost_usd")
        static let heurTier = Column("heur_tier")
        static let cfModel = Column("cf_model")
        static let cfUsd = Column("cf_usd")
        static let expSavedUsd = Column("exp_saved_usd")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case ts
        case day
        case session
        case project
        case model
        case effort
        case origin
        case promptHead = "prompt_head"
        case promptChars = "prompt_chars"
        case nRequests = "n_requests"
        case nToolCalls = "n_tool_calls"
        case nEdits = "n_edits"
        case inputTokens = "input_tokens"
        case cacheRead = "cache_read"
        case cacheCreate5m = "cache_create_5m"
        case cacheCreate1h = "cache_create_1h"
        case outputTokens = "output_tokens"
        case costUsd = "cost_usd"
        case heurTier = "heur_tier"
        case cfModel = "cf_model"
        case cfUsd = "cf_usd"
        case expSavedUsd = "exp_saved_usd"
    }
}

/// Файловый гейт инкрементального ингеста: перечитываем файл целиком, только если
/// изменились mtime/size (см. спеку 5.1 — оффсетное дочитывание запрещено).
struct AnalyticsIngestStateRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "analytics_ingest_state"

    var path: String
    var mtime: Double?
    var size: Int64?

    enum Columns {
        static let path = Column("path")
        static let mtime = Column("mtime")
        static let size = Column("size")
    }

    enum CodingKeys: String, CodingKey {
        case path
        case mtime
        case size
    }
}

/// Ключ-значение аналитики: pricing_version (триггер in-place пересчёта), last_ingest_at.
struct AnalyticsMetaRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "analytics_meta"

    var key: String
    var value: String?

    enum Columns {
        static let key = Column("key")
        static let value = Column("value")
    }

    enum CodingKeys: String, CodingKey {
        case key
        case value
    }
}

/// Наблюдение лимита Codex (primary 5h / secondary week). Upsert по UNIQUE(path, ts, window).
struct AnalyticsRateLimitRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "analytics_rate_limits"

    var path: String
    var ts: String
    var window: String
    var usedPercent: Double?

    enum Columns {
        static let path = Column("path")
        static let ts = Column("ts")
        static let window = Column("window")
        static let usedPercent = Column("used_percent")
    }

    enum CodingKeys: String, CodingKey {
        case path
        case ts
        case window
        case usedPercent = "used_percent"
    }
}

/// Наблюдение лимита провайдера. Пишется только при изменении пары
/// (used_percent, resets_at) — см. LimitsRepository.
struct LimitSnapshotRow: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    static let databaseTableName = "limit_snapshots"

    var id: Int64?
    var provider: String
    var windowMinutes: Int
    var usedPercent: Double
    var resetsAt: Int64?
    var observedAt: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column("id")
        static let provider = Column("provider")
        static let windowMinutes = Column("window_minutes")
        static let usedPercent = Column("used_percent")
        static let resetsAt = Column("resets_at")
        static let observedAt = Column("observed_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case windowMinutes = "window_minutes"
        case usedPercent = "used_percent"
        case resetsAt = "resets_at"
        case observedAt = "observed_at"
    }
}

/// Статус последнего опроса провайдера. Upsert по provider.
struct LimitFetchStateRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "limit_fetch_state"

    var provider: String
    var lastAttemptAt: Int64?
    var lastSuccessAt: Int64?
    var status: String
    var error: String?
    var retryAfterAt: Int64?

    enum Columns {
        static let provider = Column("provider")
        static let lastAttemptAt = Column("last_attempt_at")
        static let lastSuccessAt = Column("last_success_at")
        static let status = Column("status")
        static let error = Column("error")
        static let retryAfterAt = Column("retry_after_at")
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case lastAttemptAt = "last_attempt_at"
        case lastSuccessAt = "last_success_at"
        case status
        case error
        case retryAfterAt = "retry_after_at"
    }
}

