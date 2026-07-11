import XCTest
import GRDB
@testable import StatsApp

final class SyncCoordinatorSnapshotTests: XCTestCase {

    // MARK: - Tests

    /// Кладёт траты «вчера» и «сегодня», ожидает что snapshot.day.aiCostPrev = вчерашняя сумма.
    func test_snapshot_day_slice_contains_prev_cost() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        // Now = 2026-05-23 12:00:00 UTC. Lookback day = 0 → today only. Prev = вчера.
        let now = Date(timeIntervalSince1970: 1_779_873_600)  // 2026-05-23T12:00:00Z
        let today = DateUtils.daysRange(endingAt: now, lookback: 0).first!     // "2026-05-23"
        let yesterday = DateUtils.previousPeriodDays(endingAt: now, lookback: 0).first! // "2026-05-22"

        try await dbq.write { db in
            try AIUsageRow(
                id: nil, day: today, source: "claude", modelsJson: "[]",
                inputTokens: 100, outputTokens: 100, costUsd: 250.0,
                updatedAt: "2026-05-23T12:00:00Z"
            ).insert(db)
            try AIUsageRow(
                id: nil, day: yesterday, source: "claude", modelsJson: "[]",
                inputTokens: 50, outputTokens: 50, costUsd: 222.40,
                updatedAt: "2026-05-22T12:00:00Z"
            ).insert(db)
        }

        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let snapshot = try await coordinator.buildSnapshot()

        XCTAssertEqual(snapshot.day.aiCost, 250.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.day.aiCostPrev, 222.40, accuracy: 0.001)
    }

    /// Snapshot всегда пишется с актуальной версией схемы.
    func test_snapshot_uses_current_schema_version() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        let now = Date(timeIntervalSince1970: 1_779_873_600)
        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let snapshot = try await coordinator.buildSnapshot()

        XCTAssertEqual(snapshot.schemaVersion, 2)
    }
}
