import XCTest
@testable import StatsApp

/// PATH-обогащение для child-процесса ccusage. Регрессия на «env: node: No such
/// file or directory» — GUI-приложение запускалось с PATH=/usr/bin:/bin, npx
/// внутри shebang'а делает `#!/usr/bin/env node` и валился.
final class CcusageEnvTests: XCTestCase {
    func test_enrichedEnvironment_prependsBrewAndUsrLocal_whenMissing() {
        let env = CcusageFetcher.enrichedEnvironment(base: ["PATH": "/usr/bin:/bin"])
        let path = env["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init)
        XCTAssertEqual(dirs.first, "/opt/homebrew/bin")
        XCTAssertTrue(dirs.contains("/usr/local/bin"))
        XCTAssertTrue(dirs.contains("/usr/bin"))
        XCTAssertTrue(dirs.contains("/bin"))
    }

    func test_enrichedEnvironment_doesNotDuplicate_existingBrew() {
        let env = CcusageFetcher.enrichedEnvironment(
            base: ["PATH": "/opt/homebrew/bin:/usr/bin"]
        )
        let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        XCTAssertEqual(dirs.filter { $0 == "/opt/homebrew/bin" }.count, 1)
    }

    func test_enrichedEnvironment_handlesEmptyPATH() {
        let env = CcusageFetcher.enrichedEnvironment(base: [:])
        let path = env["PATH"] ?? ""
        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
    }

    func test_enrichedEnvironment_preservesOtherKeys() {
        let env = CcusageFetcher.enrichedEnvironment(
            base: ["PATH": "/bin", "HOME": "/Users/test", "FOO": "bar"]
        )
        XCTAssertEqual(env["HOME"], "/Users/test")
        XCTAssertEqual(env["FOO"], "bar")
    }
}
