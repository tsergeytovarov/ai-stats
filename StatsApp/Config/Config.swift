import Foundation

struct Config: Equatable {
    let githubToken: String
    let githubLogin: String
    let syncIntervalMinutes: Int
    let ccusageCommand: [String]
    let enabledProviders: [String]
    let aiuseApiBaseURL: String

    var githubEnabled: Bool { !githubToken.isEmpty && !githubLogin.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case githubToken = "github_token"
        case githubLogin = "github_login"
        case syncIntervalMinutes = "sync_interval_minutes"
        case ccusageCommand = "ccusage_command"
        case enabledProviders = "enabled_providers"
        case aiuseApiBaseURL = "aiuse_api_base_url"
    }

    static func decode(from data: Data) throws -> Config {
        let container = try JSONDecoder().decode(RawConfig.self, from: data)
        return Config(
            githubToken: container.githubToken,
            githubLogin: container.githubLogin,
            syncIntervalMinutes: container.syncIntervalMinutes ?? 15,
            ccusageCommand: container.ccusageCommand ?? ["npx", "-y", "ccusage@latest"],
            enabledProviders: container.enabledProviders ?? ["claude", "codex"],
            aiuseApiBaseURL: container.aiuseApiBaseURL ?? "https://aiuse.popovs.tech/api"
        )
    }

    private struct RawConfig: Decodable {
        let githubToken: String
        let githubLogin: String
        let syncIntervalMinutes: Int?
        let ccusageCommand: [String]?
        let enabledProviders: [String]?
        let aiuseApiBaseURL: String?

        enum CodingKeys: String, CodingKey {
            case githubToken = "github_token"
            case githubLogin = "github_login"
            case syncIntervalMinutes = "sync_interval_minutes"
            case ccusageCommand = "ccusage_command"
            case enabledProviders = "enabled_providers"
            case aiuseApiBaseURL = "aiuse_api_base_url"
        }
    }

    static let defaultTemplate: Data = """
    {
      "github_token": "",
      "github_login": "",
      "sync_interval_minutes": 15,
      "ccusage_command": ["npx", "-y", "ccusage@latest"],
      "enabled_providers": ["claude", "codex"],
      "aiuse_api_base_url": "https://aiuse.popovs.tech/api"
    }

    """.data(using: .utf8)!
}

enum ConfigError: Error {
    case fileNotFound
    case invalidJSON(underlying: Error)
}

enum ConfigLoader {
    /// Возвращает (Config, wasCreated). Если файл не существовал — создаст шаблон и вернёт wasCreated=true.
    static func loadOrCreate(at url: URL = Paths.configURL) throws -> (config: Config, wasCreated: Bool) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try Config.defaultTemplate.write(to: url, options: .atomic)
            let cfg = try Config.decode(from: Config.defaultTemplate)
            return (cfg, true)
        }
        do {
            let data = try Data(contentsOf: url)
            let cfg = try Config.decode(from: data)
            return (cfg, false)
        } catch let decodingError {
            throw ConfigError.invalidJSON(underlying: decodingError)
        }
    }
}
