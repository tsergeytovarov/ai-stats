import XCTest
@testable import StatsApp

@MainActor
final class DatabaseImporterTests: XCTestCase {
    private var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dbimporter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    private func touch(_ name: String) throws {
        try Data().write(to: tmpDir.appendingPathComponent(name))
    }

    private func listFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: tmpDir.path).sorted()
    }

    // MARK: - rotateBackups

    func test_rotateBackups_keepsNewestWhenOverLimit() throws {
        // 5 бэкапов с возрастающими timestamp'ами в имени.
        let timestamps = ["20251001-120000", "20251101-120000", "20251201-120000", "20260101-120000", "20260201-120000"]
        for ts in timestamps {
            try touch("\(DatabaseImporter.backupPrefix)\(ts)")
        }

        DatabaseImporter.rotateBackups(in: tmpDir, keep: 3)

        let remaining = try listFiles()
        XCTAssertEqual(remaining.count, 3, "должны остаться ровно 3 бэкапа")
        // Lexicographic sort of yyyyMMdd-HHmmss = chronological → newest суффиксы.
        XCTAssertEqual(remaining, [
            "\(DatabaseImporter.backupPrefix)20251201-120000",
            "\(DatabaseImporter.backupPrefix)20260101-120000",
            "\(DatabaseImporter.backupPrefix)20260201-120000",
        ])
    }

    func test_rotateBackups_noopWhenUnderLimit() throws {
        try touch("\(DatabaseImporter.backupPrefix)20260101-120000")
        try touch("\(DatabaseImporter.backupPrefix)20260201-120000")

        DatabaseImporter.rotateBackups(in: tmpDir, keep: 3)

        let remaining = try listFiles()
        XCTAssertEqual(remaining.count, 2)
    }

    func test_rotateBackups_noopWhenExactlyAtLimit() throws {
        for ts in ["20260101-120000", "20260201-120000", "20260301-120000"] {
            try touch("\(DatabaseImporter.backupPrefix)\(ts)")
        }

        DatabaseImporter.rotateBackups(in: tmpDir, keep: 3)

        let remaining = try listFiles()
        XCTAssertEqual(remaining.count, 3)
    }

    func test_rotateBackups_ignoresFilesWithDifferentPrefix() throws {
        // Случайные файлы в той же директории не должны трогаться.
        try touch("stats.db")
        try touch("stats.db-wal")
        try touch("config.json")
        try touch("some-other-backup")
        try touch("\(DatabaseImporter.backupPrefix)20260101-120000")
        try touch("\(DatabaseImporter.backupPrefix)20260201-120000")
        try touch("\(DatabaseImporter.backupPrefix)20260301-120000")
        try touch("\(DatabaseImporter.backupPrefix)20260401-120000")

        DatabaseImporter.rotateBackups(in: tmpDir, keep: 2)

        let remaining = Set(try listFiles())
        // Чужие файлы целы.
        XCTAssertTrue(remaining.contains("stats.db"))
        XCTAssertTrue(remaining.contains("stats.db-wal"))
        XCTAssertTrue(remaining.contains("config.json"))
        XCTAssertTrue(remaining.contains("some-other-backup"))
        // Из бэкапов остались только 2 новейших.
        XCTAssertTrue(remaining.contains("\(DatabaseImporter.backupPrefix)20260401-120000"))
        XCTAssertTrue(remaining.contains("\(DatabaseImporter.backupPrefix)20260301-120000"))
        XCTAssertFalse(remaining.contains("\(DatabaseImporter.backupPrefix)20260201-120000"))
        XCTAssertFalse(remaining.contains("\(DatabaseImporter.backupPrefix)20260101-120000"))
    }

    func test_rotateBackups_handlesEmptyDir() {
        // Не падает на пустой директории.
        XCTAssertNoThrow(DatabaseImporter.rotateBackups(in: tmpDir, keep: 3))
    }

    func test_rotateBackups_handlesMissingDir() {
        // Не падает если директории вообще нет.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertNoThrow(DatabaseImporter.rotateBackups(in: missing, keep: 3))
    }

    func test_rotateBackups_keepZeroDeletesEverything() throws {
        try touch("\(DatabaseImporter.backupPrefix)20260101-120000")
        try touch("\(DatabaseImporter.backupPrefix)20260201-120000")

        DatabaseImporter.rotateBackups(in: tmpDir, keep: 0)

        let remaining = try listFiles().filter { $0.hasPrefix(DatabaseImporter.backupPrefix) }
        XCTAssertEqual(remaining.count, 0)
    }

    func test_rotateBackups_keepNegativeIsNoop() throws {
        // Невалидное keep — defensive, не делаем ничего.
        try touch("\(DatabaseImporter.backupPrefix)20260101-120000")
        try touch("\(DatabaseImporter.backupPrefix)20260201-120000")

        DatabaseImporter.rotateBackups(in: tmpDir, keep: -1)

        let remaining = try listFiles()
        XCTAssertEqual(remaining.count, 2, "keep<0 — не трогаем ничего")
    }
}
