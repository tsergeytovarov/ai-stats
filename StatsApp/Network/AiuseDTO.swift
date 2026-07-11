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

