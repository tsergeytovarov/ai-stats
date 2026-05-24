import XCTest
import GRDB
@testable import StatsApp

final class DatabaseValidatorTests: XCTestCase {
    private var tmpURL: URL!

    override func setUp() {
        super.setUp()
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbvalidator-\(UUID().uuidString).db")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpURL)
        super.tearDown()
    }

    // MARK: - magic header

    func test_rejects_text_file_as_not_sqlite() throws {
        try "not a sqlite database, just text".write(to: tmpURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try DatabaseValidator.validate(at: tmpURL)) { err in
            guard case DatabaseValidatorError.notSqliteFile = err else {
                return XCTFail("ожидали notSqliteFile, получили \(err)")
            }
        }
    }

    func test_rejects_random_binary_with_wrong_header() throws {
        let bogus = Data([0xDE, 0xAD, 0xBE, 0xEF] + Array(repeating: UInt8(0), count: 100))
        try bogus.write(to: tmpURL)
        XCTAssertThrowsError(try DatabaseValidator.validate(at: tmpURL)) { err in
            guard case DatabaseValidatorError.notSqliteFile = err else {
                return XCTFail("ожидали notSqliteFile, получили \(err)")
            }
        }
    }

    func test_rejects_truncated_file_shorter_than_magic() throws {
        try Data([0x53, 0x51, 0x4c]).write(to: tmpURL)   // "SQL", только 3 байта
        XCTAssertThrowsError(try DatabaseValidator.validate(at: tmpURL)) { err in
            guard case DatabaseValidatorError.notSqliteFile = err else {
                return XCTFail("ожидали notSqliteFile, получили \(err)")
            }
        }
    }

    func test_rejects_nonexistent_file() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).db")
        XCTAssertThrowsError(try DatabaseValidator.validate(at: missing)) { err in
            guard case DatabaseValidatorError.openFailed = err else {
                return XCTFail("ожидали openFailed, получили \(err)")
            }
        }
    }

    // MARK: - real DB through Database.migrate

    /// Создаёт валидный stats.db с применёнными миграциями.
    private func makeValidStatsDB(at url: URL) throws {
        let pool = try DatabasePool(path: url.path)
        try Database.migrate(pool)
        try Database.checkpointAndClose(pool)
    }

    func test_accepts_freshly_migrated_stats_db() throws {
        try makeValidStatsDB(at: tmpURL)
        XCTAssertNoThrow(try DatabaseValidator.validate(at: tmpURL))
    }

    func test_rejects_sqlite_db_without_required_tables() throws {
        // Чужая SQLite — есть magic header и integrity ok, но нет наших таблиц.
        let pool = try DatabasePool(path: tmpURL.path)
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE foo (id INTEGER PRIMARY KEY)")
        }
        try Database.checkpointAndClose(pool)

        XCTAssertThrowsError(try DatabaseValidator.validate(at: tmpURL)) { err in
            guard case DatabaseValidatorError.missingRequiredTables(let missing) = err else {
                return XCTFail("ожидали missingRequiredTables, получили \(err)")
            }
            XCTAssertTrue(missing.contains("ai_usage"))
            XCTAssertTrue(missing.contains("github_activity"))
            XCTAssertTrue(missing.contains("sync_state"))
        }
    }

    func test_rejects_partial_schema_with_only_some_tables() throws {
        let pool = try DatabasePool(path: tmpURL.path)
        try pool.write { db in
            try db.execute(sql: "CREATE TABLE ai_usage (id INTEGER PRIMARY KEY)")
            // нет github_activity и sync_state
        }
        try Database.checkpointAndClose(pool)

        XCTAssertThrowsError(try DatabaseValidator.validate(at: tmpURL)) { err in
            guard case DatabaseValidatorError.missingRequiredTables(let missing) = err else {
                return XCTFail("ожидали missingRequiredTables, получили \(err)")
            }
            XCTAssertEqual(Set(missing), Set(["github_activity", "sync_state"]))
        }
    }

    // MARK: - magic header isolation

    func test_validateMagicHeader_accepts_well_formed_db() throws {
        try makeValidStatsDB(at: tmpURL)
        XCTAssertNoThrow(try DatabaseValidator.validateMagicHeader(at: tmpURL))
    }

    func test_validateMagicHeader_rejects_garbage() throws {
        try Data(repeating: 0xFF, count: 32).write(to: tmpURL)
        XCTAssertThrowsError(try DatabaseValidator.validateMagicHeader(at: tmpURL))
    }
}
