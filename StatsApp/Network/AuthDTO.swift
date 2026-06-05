import Foundation

struct AuthExchangeRequest: Codable {
    let code: String
    let verifier: String
}

struct LinkIntentResponse: Codable, Equatable {
    let linkTicket: String
    enum CodingKeys: String, CodingKey { case linkTicket = "link_ticket" }
}

struct AuthExchangeResponse: Codable, Equatable {
    let deviceToken: String
    let githubToken: String?
    let githubLogin: String?
    let friendCode: String
    let serverUserId: Int64

    enum CodingKeys: String, CodingKey {
        case deviceToken = "device_token"
        case githubToken = "github_token"
        case githubLogin = "github_login"
        case friendCode = "friend_code"
        case serverUserId = "server_user_id"
    }
}
