import Foundation

struct Config: Equatable {
    let githubToken: String
    let githubLogin: String
    let syncIntervalMinutes: Int
    let ccusageCommand: [String]
    let enabledProviders: [String]

    var githubEnabled: Bool { !githubToken.isEmpty && !githubLogin.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case githubToken = "github_token"
        case githubLogin = "github_login"
        case syncIntervalMinutes = "sync_interval_minutes"
        case ccusageCommand = "ccusage_command"
        case enabledProviders = "enabled_providers"
    }

    static func decode(from data: Data) throws -> Config {
        let container = try JSONDecoder().decode(RawConfig.self, from: data)
        return Config(
            githubToken: container.githubToken,
            githubLogin: container.githubLogin,
            syncIntervalMinutes: container.syncIntervalMinutes ?? 5,
            ccusageCommand: container.ccusageCommand ?? ["npx", "-y", "ccusage@latest"],
            enabledProviders: container.enabledProviders ?? ["claude", "codex"]
        )
    }

    private struct RawConfig: Decodable {
        let githubToken: String
        let githubLogin: String
        let syncIntervalMinutes: Int?
        let ccusageCommand: [String]?
        let enabledProviders: [String]?

        enum CodingKeys: String, CodingKey {
            case githubToken = "github_token"
            case githubLogin = "github_login"
            case syncIntervalMinutes = "sync_interval_minutes"
            case ccusageCommand = "ccusage_command"
            case enabledProviders = "enabled_providers"
        }
    }

    static let defaultTemplate: Data = """
    {
      "github_token": "",
      "github_login": "",
      "sync_interval_minutes": 5,
      "ccusage_command": ["npx", "-y", "ccusage@latest"],
      "enabled_providers": ["claude", "codex"]
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
