import XCTest
@testable import StatsApp

final class ConfigTests: XCTestCase {
    func test_decodes_full_config() throws {
        let json = """
        {
          "github_token": "ghp_xxx",
          "github_login": "popovs",
          "sync_interval_minutes": 10,
          "ccusage_command": ["npx", "-y", "ccusage@latest"],
          "enabled_providers": ["claude", "codex"]
        }
        """.data(using: .utf8)!
        let cfg = try Config.decode(from: json)
        XCTAssertEqual(cfg.githubToken, "ghp_xxx")
        XCTAssertEqual(cfg.githubLogin, "popovs")
        XCTAssertEqual(cfg.syncIntervalMinutes, 10)
        XCTAssertEqual(cfg.ccusageCommand, ["npx", "-y", "ccusage@latest"])
        XCTAssertEqual(cfg.enabledProviders, ["claude", "codex"])
    }

    func test_defaults_applied_when_fields_missing() throws {
        let json = """
        { "github_token": "", "github_login": "" }
        """.data(using: .utf8)!
        let cfg = try Config.decode(from: json)
        XCTAssertEqual(cfg.syncIntervalMinutes, 15)
        XCTAssertEqual(cfg.ccusageCommand, ["npx", "-y", "ccusage@20"],
                       "default запиннен на major 20 — не @latest, supply chain")
        XCTAssertEqual(cfg.enabledProviders, ["claude", "codex"])
    }

    func test_github_disabled_when_token_empty() throws {
        let json = """
        { "github_token": "", "github_login": "popovs" }
        """.data(using: .utf8)!
        let cfg = try Config.decode(from: json)
        XCTAssertFalse(cfg.githubEnabled)
    }

    func test_default_template_is_decodable() throws {
        let data = Config.defaultTemplate
        let cfg = try Config.decode(from: data)
        XCTAssertFalse(cfg.githubEnabled)
        XCTAssertEqual(cfg.enabledProviders, ["claude", "codex"])
    }

    func test_default_template_pins_ccusage_to_major_20() throws {
        // Защита от supply-chain атаки: дефолт не должен скатиться обратно на @latest.
        // Если перейдём на major 21+ — обнови и этот тест, и ccusage_command в defaultTemplate.
        let cfg = try Config.decode(from: Config.defaultTemplate)
        XCTAssertEqual(cfg.ccusageCommand, ["npx", "-y", "ccusage@20"])
    }

    // MARK: - ConfigLoader.clearGithubTokenField

    func test_clearGithubTokenField_preserves_other_keys() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-stats-cfg-\(UUID().uuidString).json")
        let payload: [String: Any] = [
            "github_token": "ghp_secret_value",
            "github_login": "popovs",
            "sync_interval_minutes": 10,
            "ccusage_command": ["npx", "-y", "ccusage@latest"],
            "enabled_providers": ["claude", "codex"],
            "custom_extra_field": "user-added-value"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try ConfigLoader.clearGithubTokenField(at: tmp)

        let cfg = try Config.decode(from: Data(contentsOf: tmp))
        XCTAssertEqual(cfg.githubToken, "", "github_token должен быть очищен")
        XCTAssertEqual(cfg.githubLogin, "popovs", "github_login должен остаться")
        XCTAssertEqual(cfg.syncIntervalMinutes, 10)

        let raw = try JSONSerialization.jsonObject(with: try Data(contentsOf: tmp)) as? [String: Any]
        XCTAssertEqual(raw?["custom_extra_field"] as? String, "user-added-value",
                       "неизвестные поля не должны теряться при перезаписи")
    }

    func test_clearGithubTokenField_is_noop_when_already_empty() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-stats-cfg-\(UUID().uuidString).json")
        let payload: [String: Any] = [
            "github_token": "",
            "github_login": "popovs"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: tmp)
        let originalMtime = try FileManager.default.attributesOfItem(atPath: tmp.path)[.modificationDate] as? Date
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Спим минимально, потом проверяем что mtime не изменился (файл не был переписан).
        try ConfigLoader.clearGithubTokenField(at: tmp)
        let newMtime = try FileManager.default.attributesOfItem(atPath: tmp.path)[.modificationDate] as? Date
        XCTAssertEqual(originalMtime, newMtime, "пустое значение → диск не трогаем")
    }

    func test_loadOrCreate_sets_secure_permissions_on_create() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-stats-cfg-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let (_, wasCreated) = try ConfigLoader.loadOrCreate(at: tmp)
        XCTAssertTrue(wasCreated)

        let attrs = try FileManager.default.attributesOfItem(atPath: tmp.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms, 0o600, "config.json должен быть owner-only read/write")
    }

    func test_loadOrCreate_fixes_permissions_on_existing_file() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-stats-cfg-\(UUID().uuidString).json")
        let payload = Config.defaultTemplate
        try payload.write(to: tmp)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: tmp.path
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try ConfigLoader.loadOrCreate(at: tmp)

        let attrs = try FileManager.default.attributesOfItem(atPath: tmp.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms, 0o600, "loadOrCreate должен defensive-fix'ить mode")
    }

    // MARK: - validateAiuseBaseURL

    func test_validateAiuseBaseURL_accepts_https() throws {
        let url = try AppContainer.validateAiuseBaseURL("https://aiuse.popovs.tech/api")
        XCTAssertEqual(url.absoluteString, "https://aiuse.popovs.tech/api")
    }

    func test_validateAiuseBaseURL_rejects_http() {
        XCTAssertThrowsError(try AppContainer.validateAiuseBaseURL("http://evil.example.com/api")) { err in
            guard case ConfigError.insecureBaseURL(let scheme) = err else {
                return XCTFail("ожидали insecureBaseURL, получили \(err)")
            }
            XCTAssertEqual(scheme, "http")
        }
    }

    func test_validateAiuseBaseURL_rejects_other_schemes() {
        XCTAssertThrowsError(try AppContainer.validateAiuseBaseURL("ftp://example.com/")) { err in
            guard case ConfigError.insecureBaseURL = err else {
                return XCTFail("ожидали insecureBaseURL, получили \(err)")
            }
        }
        XCTAssertThrowsError(try AppContainer.validateAiuseBaseURL("file:///tmp/api")) { err in
            guard case ConfigError.insecureBaseURL = err else {
                return XCTFail("ожидали insecureBaseURL, получили \(err)")
            }
        }
    }

    func test_validateAiuseBaseURL_falls_back_to_default_on_empty() throws {
        let url = try AppContainer.validateAiuseBaseURL("")
        XCTAssertEqual(url.absoluteString, "https://aiuse.popovs.tech/api")
    }
}
