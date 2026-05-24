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

struct GitHubRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "github_activity"

    var id: Int64?
    var day: String
    var repo: String
    var commits: Int64
    var updatedAt: String

    enum Columns {
        static let id = Column("id")
        static let day = Column("day")
        static let repo = Column("repo")
        static let commits = Column("commits")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case repo
        case commits
        case updatedAt = "updated_at"
    }
}

struct GitHubLOCDailyRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "github_loc_daily"

    var id: Int64?
    var day: String
    var repo: String
    var additions: Int64
    var deletions: Int64
    var updatedAt: String

    enum Columns {
        static let id = Column("id")
        static let day = Column("day")
        static let repo = Column("repo")
        static let additions = Column("additions")
        static let deletions = Column("deletions")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case repo
        case additions
        case deletions
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

/// Кэш профиля друга — имя/аватарка/sharing для оффлайн-рендера.
struct FriendProfileRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "friend_profiles"

    var friendCode: String
    var displayName: String
    var sharingEnabled: Bool
    var avatarBlob: Data?
    var avatarMime: String?
    var avatarEtag: String?
    var lastFetchedAt: Double

    enum Columns {
        static let friendCode = Column("friend_code")
        static let displayName = Column("display_name")
        static let sharingEnabled = Column("sharing_enabled")
        static let avatarBlob = Column("avatar_blob")
        static let avatarMime = Column("avatar_mime")
        static let avatarEtag = Column("avatar_etag")
        static let lastFetchedAt = Column("last_fetched_at")
    }

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case sharingEnabled = "sharing_enabled"
        case avatarBlob = "avatar_blob"
        case avatarMime = "avatar_mime"
        case avatarEtag = "avatar_etag"
        case lastFetchedAt = "last_fetched_at"
    }
}

/// Кэш ответов /api/leaderboard за каждый period. payload_json = encoded LeaderboardResponse.
struct LeaderboardCacheRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "leaderboard_cache"

    var period: String
    var fetchedAt: Double
    var payloadJson: String

    enum Columns {
        static let period = Column("period")
        static let fetchedAt = Column("fetched_at")
        static let payloadJson = Column("payload_json")
    }

    enum CodingKeys: String, CodingKey {
        case period
        case fetchedAt = "fetched_at"
        case payloadJson = "payload_json"
    }
}

/// Snapshot ожидающий отправки на сервер. hour_bucket = unix seconds (UTC).
struct PendingSnapshotRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "pending_snapshots"

    var hourBucket: Int64
    var tokensInput: Int64
    var tokensOutput: Int64
    var attempts: Int = 0
    var lastError: String?

    enum Columns {
        static let hourBucket = Column("hour_bucket")
        static let tokensInput = Column("tokens_input")
        static let tokensOutput = Column("tokens_output")
        static let attempts = Column("attempts")
        static let lastError = Column("last_error")
    }

    enum CodingKeys: String, CodingKey {
        case hourBucket = "hour_bucket"
        case tokensInput = "tokens_input"
        case tokensOutput = "tokens_output"
        case attempts
        case lastError = "last_error"
    }
}
