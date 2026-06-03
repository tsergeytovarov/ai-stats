import Foundation

// MARK: - profiles

struct ProfileCreateRequest: Codable {
    let displayName: String
    let avatarB64: String?
    let avatarMime: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarB64 = "avatar_b64"
        case avatarMime = "avatar_mime"
    }
}

struct ProfileCreateResponse: Codable {
    let friendCode: String
    let apiSecret: String
    let serverUserId: Int64

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case apiSecret = "api_secret"
        case serverUserId = "server_user_id"
    }
}

struct ProfileUpdateRequest: Codable {
    let displayName: String?
    let avatarB64: String?
    let avatarMime: String?
    let sharingEnabled: Bool?
    let globalOptIn: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarB64 = "avatar_b64"
        case avatarMime = "avatar_mime"
        case sharingEnabled = "sharing_enabled"
        case globalOptIn = "global_opt_in"
    }
}

struct ProfileResponse: Codable {
    let friendCode: String
    let displayName: String
    let sharingEnabled: Bool
    let globalOptIn: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case sharingEnabled = "sharing_enabled"
        case globalOptIn = "global_opt_in"
        case createdAt = "created_at"
    }
}

struct RegenerateFriendCodeResponse: Codable {
    let friendCode: String
    let friendshipsDropped: Int

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case friendshipsDropped = "friendships_dropped"
    }
}

// MARK: - snapshots

struct SnapshotItem: Codable, Equatable {
    let hourBucket: String   // ISO 8601, UTC
    let tokensInput: Int64
    let tokensOutput: Int64

    enum CodingKeys: String, CodingKey {
        case hourBucket = "hour_bucket"
        case tokensInput = "tokens_input"
        case tokensOutput = "tokens_output"
    }
}

struct SnapshotsBatch: Codable {
    let snapshots: [SnapshotItem]
}

struct SnapshotsResponse: Codable {
    let accepted: Int
}

// MARK: - friends

struct AddFriendRequest: Codable {
    let friendCode: String

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
    }
}

struct RemoveFriendRequest: Codable {
    let block: Bool
}

struct FriendDTO: Codable, Identifiable, Equatable {
    let friendCode: String
    let displayName: String
    let sharingEnabled: Bool
    let addedAt: String

    var id: String { friendCode }

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case sharingEnabled = "sharing_enabled"
        case addedAt = "added_at"
    }
}

struct FriendsListResponse: Codable {
    let friends: [FriendDTO]
}

// MARK: - leaderboard

struct LeaderboardEntry: Codable, Identifiable, Equatable {
    let friendCode: String
    let displayName: String
    let rank: Int
    let previousRank: Int?
    let tokensTotal: Int64
    let isMe: Bool

    var id: String { friendCode }

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case rank
        case previousRank = "previous_rank"
        case tokensTotal = "tokens_total"
        case isMe = "is_me"
    }
}

struct LeaderboardResponse: Codable {
    let period: String
    let asOf: String
    let entries: [LeaderboardEntry]

    enum CodingKeys: String, CodingKey {
        case period
        case asOf = "as_of"
        case entries
    }
}

// MARK: - blocks

struct BlockDTO: Codable, Identifiable, Equatable {
    let friendCode: String
    let displayName: String
    let blockedAt: String

    var id: String { friendCode }

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case blockedAt = "blocked_at"
    }
}

struct BlocksListResponse: Codable {
    let blocked: [BlockDTO]
}
