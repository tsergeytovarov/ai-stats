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
        XCTAssertEqual(cfg.syncIntervalMinutes, 5)
        XCTAssertEqual(cfg.ccusageCommand, ["npx", "-y", "ccusage@latest"])
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
}
