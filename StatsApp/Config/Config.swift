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

enum ConfigError: Error, LocalizedError {
    case fileNotFound
    case invalidJSON(underlying: Error)
    case insecureBaseURL(scheme: String?)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "config файл не найден"
        case .invalidJSON(let err):
            return "невалидный JSON в config: \(err.localizedDescription)"
        case .insecureBaseURL(let scheme):
            let s = scheme ?? "<none>"
            return "aiuse_api_base_url должен быть https:// (получено: \(s)://). Token утечёт на plain-text endpoint."
        }
    }
}

enum ConfigLoader {
    /// Возвращает (Config, wasCreated). Если файл не существовал — создаст шаблон и вернёт wasCreated=true.
    /// При создании / каждом чтении выставляет права 0600 на файл (даже если до этого был 0644).
    static func loadOrCreate(at url: URL = Paths.configURL) throws -> (config: Config, wasCreated: Bool) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try Config.defaultTemplate.write(to: url, options: .atomic)
            setSecurePermissions(at: url)
            let cfg = try Config.decode(from: Config.defaultTemplate)
            return (cfg, true)
        }
        // Defensive: даже если файл существовал — приводим mode к 0600.
        setSecurePermissions(at: url)
        do {
            let data = try Data(contentsOf: url)
            let cfg = try Config.decode(from: data)
            return (cfg, false)
        } catch let decodingError {
            throw ConfigError.invalidJSON(underlying: decodingError)
        }
    }

    /// Перезаписывает поле `github_token` пустой строкой, сохраняя остальные ключи
    /// (включая неизвестные нам — пользователь мог добавить comments или extra fields).
    /// Используется после миграции токена в Keychain.
    static func clearGithubTokenField(at url: URL = Paths.configURL) throws {
        let data = try Data(contentsOf: url)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        // Если уже пусто — не дёргаем диск.
        if let current = json["github_token"] as? String, current.isEmpty {
            return
        }
        json["github_token"] = ""
        let newData = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try newData.write(to: url, options: .atomic)
        setSecurePermissions(at: url)
    }

    /// Выставляет owner read/write only (0600) на файл. Если не получилось — молча
    /// пропускаем (FS может не поддерживать POSIX permissions, e.g. iCloud-синхрон).
    static func setSecurePermissions(at url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
