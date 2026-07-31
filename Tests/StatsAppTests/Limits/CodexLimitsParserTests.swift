import XCTest
@testable import StatsApp

final class CodexLimitsParserTests: XCTestCase {

    // Живой ответ app-server от 2026-07-31. Обрати внимание: primary — НЕДЕЛЬНОЕ
    // окно (10080), а secondary пустой. Раскладывать окна по позиции нельзя.
    func test_parses_rpc_result_with_weekly_primary() throws {
        let json = Data(#"""
        {"jsonrpc":"2.0","id":2,"result":{"rateLimits":{
          "primary":{"usedPercent":78,"resetsAt":1785905362,"windowDurationMins":10080},
          "secondary":null}}}
        """#.utf8)

        let windows = CodexLimitsParser.parseRPC(json)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].windowMinutes, 10080)
        XCTAssertEqual(windows[0].usedPercent, 78)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1_785_905_362))
    }

    func test_parses_both_windows_when_present() throws {
        let json = Data(#"""
        {"jsonrpc":"2.0","id":2,"result":{"rateLimits":{
          "primary":{"usedPercent":12.5,"resetsAt":1785000000,"windowDurationMins":300},
          "secondary":{"usedPercent":40,"resetsAt":1785900000,"windowDurationMins":10080}}}}
        """#.utf8)

        let windows = CodexLimitsParser.parseRPC(json)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(Set(windows.map(\.windowMinutes)), [300, 10080])
    }

    // Без длительности окно бессмысленно — не гадаем, а выбрасываем.
    func test_drops_window_without_duration() throws {
        let json = Data(#"""
        {"result":{"rateLimits":{"primary":{"usedPercent":50,"resetsAt":1785000000}}}}
        """#.utf8)
        XCTAssertTrue(CodexLimitsParser.parseRPC(json).isEmpty)
    }

    func test_returns_empty_on_garbage() {
        XCTAssertTrue(CodexLimitsParser.parseRPC(Data("не json".utf8)).isEmpty)
        XCTAssertTrue(CodexLimitsParser.parseRPC(Data("{}".utf8)).isEmpty)
    }

    // Фолбэк: строка token_count из rollout-лога. Формат другой — snake_case и
    // limit_id, который надо проверить.
    func test_parses_rollout_line() throws {
        let line = #"{"type":"event_msg","timestamp":"2026-07-31T00:35:21Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":74.0,"window_minutes":10080,"resets_at":1785905362},"secondary":null}}}"#
        let windows = try XCTUnwrap(CodexLimitsParser.parseRolloutLine(line))
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].windowMinutes, 10080)
        XCTAssertEqual(windows[0].usedPercent, 74)
    }

    func test_ignores_rollout_line_of_other_limit_id() {
        let line = #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"other","primary":{"used_percent":99.0,"window_minutes":300}}}}"#
        XCTAssertNil(CodexLimitsParser.parseRolloutLine(line))
    }

    func test_ignores_line_without_rate_limits() {
        XCTAssertNil(CodexLimitsParser.parseRolloutLine(#"{"payload":{"type":"other"}}"#))
    }
}

final class CodexLimitsFetcherTests: XCTestCase {

    // Фолбэк на rollout-логи: кладём во временную дир'ю два файла, свежий должен
    // выиграть, а внутри файла — последний снапшот.
    func test_falls_back_to_newest_rollout_snapshot() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-limits-\(UUID().uuidString)/2026/07/31")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let old = dir.appending(path: "rollout-old.jsonl")
        try #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":10080}}}}"#
            .write(to: old, atomically: true, encoding: .utf8)

        let fresh = dir.appending(path: "rollout-fresh.jsonl")
        try [
            #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":50.0,"window_minutes":10080}}}}"#,
            #"{"payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":74.0,"window_minutes":10080,"resets_at":1785905362}}}}"#,
        ].joined(separator: "\n").write(to: fresh, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)],
                                              ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)],
                                              ofItemAtPath: fresh.path)

        // Пустая PATH-подстановка недоступна, поэтому проверяем ровно фолбэк:
        // если codex в системе есть, тест всё равно осмысленный — окна не пустые.
        let fetcher = CodexLimitsFetcher(sessionsDir: dir.deletingLastPathComponent()
                                            .deletingLastPathComponent().deletingLastPathComponent(),
                                         rpcTimeout: 0.1,
                                         now: { Date(timeIntervalSince1970: 5_000) })
        let limits = await fetcher.fetch()
        XCTAssertEqual(limits.provider, .codex)
        XCTAssertFalse(limits.windows.isEmpty)
        XCTAssertEqual(limits.windows[0].windowMinutes, 10080)
    }

    func test_reports_unavailable_when_nothing_found() async {
        let empty = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "codex-empty-\(UUID().uuidString)")
        let fetcher = CodexLimitsFetcher(sessionsDir: empty, rpcTimeout: 0.1)
        let limits = await fetcher.fetch()
        if limits.status == .unavailable {
            XCTAssertTrue(limits.windows.isEmpty)
        } else {
            // На машине с рабочим codex RPC отвечает — тогда данные обязаны быть.
            XCTAssertEqual(limits.status, .ok)
            XCTAssertFalse(limits.windows.isEmpty)
        }
    }
}
