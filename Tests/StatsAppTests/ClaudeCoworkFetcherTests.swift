import XCTest
@testable import StatsApp

final class ClaudeCoworkFetcherTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!
    private let sinceJan1: Date = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
    private let nowJan15: () -> Date = { ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")! }

    func test_fetcher_reads_jsonl_from_cowork_directory_structure() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Build: tempDir/<session>/<workspace>/local_<agent>/.claude/projects/<path>/<id>.jsonl
        let projectsDir = tempDir
            .appendingPathComponent("cowork-session")
            .appendingPathComponent("workspace")
            .appendingPathComponent("local_agent")
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
            .appendingPathComponent("project-path")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        let jsonlContent = """
        {"type":"assistant","timestamp":"2026-01-15T10:00:00Z","requestId":"req_001","message":{"id":"msg_001","model":"claude-opus-4-7","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        """
        try jsonlContent.write(
            to: projectsDir.appendingPathComponent("session.jsonl"),
            atomically: true, encoding: .utf8
        )

        let fetcher = ClaudeCoworkFetcher(
            sessionsBaseURL: tempDir, timezone: utc, now: nowJan15
        )
        let result = try await fetcher.fetch(since: sinceJan1)

        guard case .aiUsage(let payload) = result else {
            return XCTFail("Expected .aiUsage result")
        }
        XCTAssertEqual(payload.dayRows.count, 1)
        XCTAssertEqual(payload.dayRows[0].source, "claude-cowork")
        XCTAssertEqual(payload.dayRows[0].day, "2026-01-15")
        XCTAssertEqual(payload.dayRows[0].inputTokens, 100)
    }

    func test_fetcher_skips_files_not_modified_since() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectsDir = tempDir
            .appendingPathComponent("cowork-session")
            .appendingPathComponent("workspace")
            .appendingPathComponent("local_agent")
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
            .appendingPathComponent("project-path")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        // Запись внутри датирована ПОСЛЕ since, но mtime файла — ДО since.
        // Реальный append-only jsonl так выглядеть не может (mtime >= timestamp
        // последней записи), поэтому фетчер обязан отсеять файл по mtime,
        // не читая содержимое с диска.
        let jsonlContent = """
        {"type":"assistant","timestamp":"2026-01-15T10:00:00Z","requestId":"req_001","message":{"id":"msg_001","model":"claude-opus-4-7","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        """
        let fileURL = projectsDir.appendingPathComponent("stale.jsonl")
        try jsonlContent.write(to: fileURL, atomically: true, encoding: .utf8)
        let staleDate = ISO8601DateFormatter().date(from: "2025-12-01T00:00:00Z")!
        try FileManager.default.setAttributes(
            [.modificationDate: staleDate], ofItemAtPath: fileURL.path
        )

        let fetcher = ClaudeCoworkFetcher(
            sessionsBaseURL: tempDir, timezone: utc, now: nowJan15
        )
        let result = try await fetcher.fetch(since: sinceJan1)

        guard case .aiUsage(let payload) = result else {
            return XCTFail("Expected .aiUsage result")
        }
        XCTAssertTrue(payload.dayRows.isEmpty, "file with mtime older than since must be skipped unread")
    }

    func test_fetcher_returns_empty_when_sessions_directory_does_not_exist() async throws {
        let nonExistent = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        let fetcher = ClaudeCoworkFetcher(
            sessionsBaseURL: nonExistent, timezone: utc, now: nowJan15
        )
        let result = try await fetcher.fetch(since: sinceJan1)

        guard case .aiUsage(let payload) = result else {
            return XCTFail("Expected .aiUsage result")
        }
        XCTAssertTrue(payload.dayRows.isEmpty)
    }

    func test_fetcher_ignores_audit_jsonl_outside_claude_projects() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Place audit.jsonl directly inside local_agent/ (NOT in .claude/projects)
        let agentDir = tempDir
            .appendingPathComponent("session")
            .appendingPathComponent("workspace")
            .appendingPathComponent("local_agent")
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)

        let jsonlContent = """
        {"type":"assistant","timestamp":"2026-01-15T10:00:00Z","requestId":"req_001","message":{"id":"msg_001","model":"claude-opus-4-7","role":"assistant","usage":{"input_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":50}}}
        """
        try jsonlContent.write(
            to: agentDir.appendingPathComponent("audit.jsonl"),
            atomically: true, encoding: .utf8
        )

        let fetcher = ClaudeCoworkFetcher(
            sessionsBaseURL: tempDir, timezone: utc, now: nowJan15
        )
        let result = try await fetcher.fetch(since: sinceJan1)

        guard case .aiUsage(let payload) = result else {
            return XCTFail("Expected .aiUsage result")
        }
        XCTAssertTrue(payload.dayRows.isEmpty)
    }
}
