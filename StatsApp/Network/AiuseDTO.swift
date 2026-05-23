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

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarB64 = "avatar_b64"
        case avatarMime = "avatar_mime"
        case sharingEnabled = "sharing_enabled"
    }
}

struct ProfileResponse: Codable {
    let friendCode: String
    let displayName: String
    let sharingEnabled: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case friendCode = "friend_code"
        case displayName = "display_name"
        case sharingEnabled = "sharing_enabled"
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
