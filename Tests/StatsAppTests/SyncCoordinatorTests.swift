import XCTest
import GRDB
@testable import StatsApp

final class SyncCoordinatorTests: XCTestCase {
    actor MockFetcher: Fetcher {
        var callCount = 0
        var lastSince: Date?
        var result: FetchResult
        init(result: FetchResult) { self.result = result }
        func fetch(since: Date) async throws -> FetchResult {
            callCount += 1
            lastSince = since
            return result
        }
    }

    func test_first_run_uses_365d_backfill_window() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        let fetcher = MockFetcher(result: .aiUsage([]))
        let coordinator = await SyncCoordinator(db: dbq, now: { Date(timeIntervalSince1970: 1716336000) })

        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let since = await fetcher.lastSince!
        let expectedSince = Calendar(identifier: .gregorian).date(byAdding: .day, value: -365, to: Date(timeIntervalSince1970: 1716336000))!
        XCTAssertEqual(since.timeIntervalSince1970, expectedSince.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_second_run_uses_7d_window() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try await dbq.write { db in
            let s = SyncStateRow(source: "ccusage", lastSyncAt: "2024-05-20T00:00:00Z", lastError: nil)
            try s.insert(db)
        }
        let fetcher = MockFetcher(result: .aiUsage([]))
        let coordinator = await SyncCoordinator(db: dbq, now: { Date(timeIntervalSince1970: 1716336000) })

        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let since = await fetcher.lastSince!
        let expectedSince = Calendar(identifier: .gregorian).date(byAdding: .day, value: -7, to: Date(timeIntervalSince1970: 1716336000))!
        XCTAssertEqual(since.timeIntervalSince1970, expectedSince.timeIntervalSince1970, accuracy: 1.0)
    }

    func test_single_flight_skips_concurrent_runs() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        actor SlowFetcher: Fetcher {
            var callCount = 0
            func fetch(since: Date) async throws -> FetchResult {
                callCount += 1
                try await Task.sleep(nanoseconds: 200_000_000)
                return .aiUsage([])
            }
        }

        let fetcher = SlowFetcher()
        let coordinator = await SyncCoordinator(db: dbq, now: Date.init)

        async let r1: Void = coordinator.runOnce(source: "ccusage", fetchers: [fetcher])
        async let r2: Void = coordinator.runOnce(source: "ccusage", fetchers: [fetcher])
        _ = try await (r1, r2)

        let count = await fetcher.callCount
        XCTAssertEqual(count, 1, "second concurrent run must be skipped by single-flight")
    }

    func test_writes_rows_and_sync_state() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        let row = AIUsageRow(id: nil, day: "2024-05-22", source: "claude", modelsJson: "[]", inputTokens: 100, outputTokens: 50, costUsd: 1.0, updatedAt: "now")
        let fetcher = MockFetcher(result: .aiUsage([row]))
        let coordinator = await SyncCoordinator(db: dbq, now: Date.init)

        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        try await dbq.read { db in
            XCTAssertEqual(try AIUsageRow.fetchCount(db), 1)
            let state = try SyncStateRow.fetchOne(db)!
            XCTAssertEqual(state.source, "ccusage")
            XCTAssertNil(state.lastError)
        }
    }
}
