import Foundation

enum AiuseAPIError: Error, Equatable {
    case missingSecret           // нет в Keychain
    case invalidURL
    case transport(String)       // network failure
    case http(status: Int, body: String)
    case decoding(String)
    case unexpected
}
