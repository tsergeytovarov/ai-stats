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

    // MARK: - Поля советника (C9, спека 2.3)

    private let advisorNow = ISO8601DateFormatter().date(from: "2026-07-11T12:00:00Z")!

    private func seedAnalyticsTurns(_ dbq: DatabaseQueue, count: Int, exp: Double,
                                    promptHead: String) async throws {
        try await dbq.write { db in
            for i in 0..<count {
                var row = AnalyticsTurnRow(
                    id: nil, source: "codex", ts: "2026-07-05T10:00:00Z-\(i)",
                    day: "2026-07-05", session: "s\(i)", project: "/p", model: "gpt-5.5",
                    origin: "human", promptHead: promptHead, promptChars: 20,
                    nRequests: 1, inputTokens: 1000, outputTokens: 0,
                    costUsd: 5.0, expSavedUsd: exp
                )
                try row.insert(db)
            }
        }
    }

    /// Нет ходов → карточка .noData → поля советника nil (строка Large скрыта).
    func test_snapshot_advisor_nil_when_no_data() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        let coordinator = await SyncCoordinator(db: dbq, now: { self.advisorNow })

        let snapshot = try await coordinator.buildSnapshot()

        XCTAssertNil(snapshot.advisorComputedAt)
        XCTAssertNil(snapshot.leakUsdPerMonth)
        XCTAssertNil(snapshot.topLeakTitle)
    }

    /// <50 ходов → .tooFewData → поля советника nil (строка скрыта, не «утечек нет»).
    func test_snapshot_advisor_nil_when_too_few_data() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try await seedAnalyticsTurns(dbq, count: 10, exp: 0.5, promptHead: "ты — рерайтер роль x")
        let coordinator = await SyncCoordinator(db: dbq, now: { self.advisorNow })

        let snapshot = try await coordinator.buildSnapshot()

        XCTAssertNil(snapshot.advisorComputedAt)
        XCTAssertNil(snapshot.leakUsdPerMonth)
        XCTAssertNil(snapshot.topLeakTitle)
    }

    /// ≥50 ходов + кластер-утечка → поля заполнены (строка «Утекает ≈$X/мес · title»).
    func test_snapshot_advisor_set_when_ready_with_leak() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try await seedAnalyticsTurns(dbq, count: 60, exp: 0.5, promptHead: "ты — рерайтер роль x")
        let coordinator = await SyncCoordinator(db: dbq, now: { self.advisorNow })

        let snapshot = try await coordinator.buildSnapshot()

        XCTAssertNotNil(snapshot.advisorComputedAt)
        XCTAssertEqual(snapshot.leakUsdPerMonth ?? -1, 30.0, accuracy: 1e-9)  // 60 × 0.5
        XCTAssertEqual(snapshot.topLeakTitle, "Регулярная роль: Рерайтер роль x")
    }

    /// ≥50 ходов, но Σexp ≤ $1 → computedAt задан, title nil (строка «Утечек не видно»).
    func test_snapshot_advisor_ready_no_leaks_has_computedAt_but_nil_title() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try await seedAnalyticsTurns(dbq, count: 50, exp: 0.001, promptHead: "короткий вопрос")
        let coordinator = await SyncCoordinator(db: dbq, now: { self.advisorNow })

        let snapshot = try await coordinator.buildSnapshot()

        XCTAssertNotNil(snapshot.advisorComputedAt)
        XCTAssertNil(snapshot.topLeakTitle)
        let leakCents = Int(((snapshot.leakUsdPerMonth ?? 0) * 100).rounded())
        XCTAssertLessThanOrEqual(leakCents, 100)
    }
}
