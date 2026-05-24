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

    func test_extraSearchPaths_doesNotIncludeHomeRelativePath() {
        // Регрессия на security pass #3: home-writable дир'ы убраны,
        // bun-юзеры добавляют ~/.bun/bin в shell PATH сами.
        let paths = CcusageFetcher.extraSearchPaths(home: "/Users/anybody")
        XCTAssertFalse(paths.contains(where: { $0.hasPrefix("/Users/") }),
                       "extraSearchPaths не должен включать home-relative dir'ы (PATH-hijack)")
        XCTAssertTrue(paths.contains("/opt/homebrew/bin"))
        XCTAssertTrue(paths.contains("/usr/local/bin"))
    }

    // MARK: - validateCommandHead

    func test_validateCommandHead_acceptsNpx() throws {
        XCTAssertNoThrow(try CcusageFetcher.validateCommandHead("npx"))
    }

    func test_validateCommandHead_acceptsBunx() throws {
        XCTAssertNoThrow(try CcusageFetcher.validateCommandHead("bunx"))
    }

    func test_validateCommandHead_acceptsAbsolutePath() throws {
        XCTAssertNoThrow(try CcusageFetcher.validateCommandHead("/opt/homebrew/bin/npx"))
        XCTAssertNoThrow(try CcusageFetcher.validateCommandHead("/usr/local/bin/bunx"))
    }

    func test_validateCommandHead_rejectsArbitraryCommand() {
        // Главный сценарий, который мы закрываем: подмена команды в config.json.
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead("rm")) { err in
            guard case CcusageError.invalidCommandPrefix = err else {
                return XCTFail("ожидали invalidCommandPrefix, получили \(err)")
            }
        }
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead("curl"))
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead("sh"))
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead("bash"))
    }

    func test_validateCommandHead_rejectsEmptyString() {
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead(""))
    }

    func test_validateCommandHead_rejectsRelativePathTraversal() {
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead("../npx"))
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead("./npx"))
    }

    func test_validateCommandHead_rejectsDotDotInAbsolutePath() {
        // Даже абсолютный путь с `..` отвергаем — это попытка обойти allowlist.
        XCTAssertThrowsError(try CcusageFetcher.validateCommandHead("/usr/bin/../bin/sh")) { err in
            guard case CcusageError.invalidCommandPrefix = err else {
                return XCTFail("ожидали invalidCommandPrefix, получили \(err)")
            }
        }
    }
}
