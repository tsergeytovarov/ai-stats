import XCTest
import GRDB
@testable import StatsApp

final class LimitModelsTests: XCTestCase {

    private func limits(_ windows: [LimitWindow]) -> ProviderLimits {
        ProviderLimits(provider: .claude, windows: windows, status: .ok,
                       fetchedAt: Date(timeIntervalSince1970: 1_785_000_000), error: nil)
    }

    // Кольцо заполняется по окну с самым ранним сбросом — это ответ на вопрос
    // «сколько осталось в ближайшее время», а не «где я вообще».
    func test_ring_window_is_the_one_resetting_soonest() {
        let five = LimitWindow(windowMinutes: 300, usedPercent: 12,
                               resetsAt: Date(timeIntervalSince1970: 1_785_010_000))
        let week = LimitWindow(windowMinutes: 10080, usedPercent: 95,
                               resetsAt: Date(timeIntervalSince1970: 1_785_900_000))
        XCTAssertEqual(limits([week, five]).ringWindow, five)
    }

    // Времени сброса нет ни у одного окна — берём самое короткое по длительности.
    func test_ring_window_falls_back_to_shortest_when_no_reset_times() {
        let week = LimitWindow(windowMinutes: 10080, usedPercent: 40, resetsAt: nil)
        let month = LimitWindow(windowMinutes: 43200, usedPercent: 80, resetsAt: nil)
        XCTAssertEqual(limits([month, week]).ringWindow, week)
    }

    func test_ring_window_is_nil_without_windows() {
        XCTAssertNil(limits([]).ringWindow)
    }

    // Заливка идёт по ближайшему сбросу, даже когда другое окно куда хуже:
    // кольцо отвечает на «сколько осталось в ближайшее время», а не «где я
    // вообще». Про «где вообще» есть полоски всех окон в попапе.
    func test_ring_window_ignores_a_worse_but_later_window() {
        let five = LimitWindow(windowMinutes: 300, usedPercent: 0,
                               resetsAt: Date(timeIntervalSince1970: 1_785_010_000))
        let week = LimitWindow(windowMinutes: 10080, usedPercent: 95,
                               resetsAt: Date(timeIntervalSince1970: 1_785_900_000))
        XCTAssertEqual(limits([five, week]).ringWindow, five)
    }
}

final class LimitsMigrationTests: XCTestCase {

    func test_migration_creates_limit_tables() throws {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)

        let tables = try queue.read { db in
            try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        XCTAssertTrue(tables.contains("limit_snapshots"))
        XCTAssertTrue(tables.contains("limit_fetch_state"))
    }

    func test_snapshot_row_roundtrip() throws {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)

        try queue.write { db in
            var row = LimitSnapshotRow(id: nil, provider: "codex", windowMinutes: 10080,
                                       usedPercent: 78, resetsAt: 1_785_905_362,
                                       observedAt: 1_785_000_000)
            try row.insert(db)
        }
        let fetched = try queue.read { db in try LimitSnapshotRow.fetchAll(db) }
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].provider, "codex")
        XCTAssertEqual(fetched[0].windowMinutes, 10080)
        XCTAssertEqual(fetched[0].usedPercent, 78)
        XCTAssertEqual(fetched[0].resetsAt, 1_785_905_362)
    }

    func test_fetch_state_row_roundtrip() throws {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)

        try queue.write { db in
            try LimitFetchStateRow(provider: "claude", lastAttemptAt: 100, lastSuccessAt: 90,
                                   status: "throttled", error: nil, retryAfterAt: 3682)
                .insert(db, onConflict: .replace)
        }
        let fetched = try queue.read { db in try LimitFetchStateRow.fetchAll(db) }
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].status, "throttled")
        XCTAssertEqual(fetched[0].retryAfterAt, 3682)
    }
}
