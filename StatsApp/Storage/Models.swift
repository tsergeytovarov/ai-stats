import Foundation
import GRDB

struct AIUsageRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "ai_usage"

    var id: Int64?
    var day: String
    var source: String
    var modelsJson: String
    var inputTokens: Int64
    var outputTokens: Int64
    var costUsd: Double
    var updatedAt: String

    enum Columns {
        static let id = Column("id")
        static let day = Column("day")
        static let source = Column("source")
        static let modelsJson = Column("models_json")
        static let inputTokens = Column("input_tokens")
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

struct GitHubLOCWeeklyRow: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "github_loc_weekly"

    var id: Int64?
    var weekStart: String
    var repo: String
    var additions: Int64
    var deletions: Int64
    var updatedAt: String

    enum Columns {
        static let id = Column("id")
        static let weekStart = Column("week_start")
        static let repo = Column("repo")
        static let additions = Column("additions")
        static let deletions = Column("deletions")
        static let updatedAt = Column("updated_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case weekStart = "week_start"
        case repo
        case additions
        case deletions
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
