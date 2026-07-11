import XCTest
import GRDB
@testable import StatsApp

@MainActor
final class AnalyticsScheduleTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-07-11T12:00:00Z")!

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func seedLastIngest(_ dbq: DatabaseQueue, at date: Date) async throws {
        let value = iso(date)
        try await dbq.write { db in
            try AnalyticsMetaRow(key: "last_ingest_at", value: value).insert(db)
        }
    }

    /// Прошло <1ч с прошлого ингеста → скип, ингест не вызывается.
    func test_skips_when_last_ingest_within_hour() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try await seedLastIngest(dbq, at: now.addingTimeInterval(-30 * 60))  // 30 мин назад

        var ran = false
        let coordinator = SyncCoordinator(db: dbq, now: { self.now },
                                          analyticsIngest: { ran = true })

        let did = await coordinator.maybeRunAnalyticsIngest()

        XCTAssertFalse(did)
        XCTAssertFalse(ran)
    }

    /// Прошло >1ч → ингест выполняется, метка last_ingest_at обновляется на now.
    func test_runs_when_last_ingest_over_hour() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)
        try await seedLastIngest(dbq, at: now.addingTimeInterval(-2 * 3600))  // 2ч назад

        var ran = false
        let coordinator = SyncCoordinator(db: dbq, now: { self.now },
                                          analyticsIngest: { ran = true })

        let did = await coordinator.maybeRunAnalyticsIngest()

        XCTAssertTrue(did)
        XCTAssertTrue(ran)

        let stored = try await dbq.read { db in
            try AnalyticsMetaRow.filter(AnalyticsMetaRow.Columns.key == "last_ingest_at").fetchOne(db)?.value
        }
        XCTAssertEqual(stored, iso(now))
    }

    /// Первый запуск (метки нет) → ингест выполняется.
    func test_runs_when_no_previous_ingest() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        var ran = false
        let coordinator = SyncCoordinator(db: dbq, now: { self.now },
                                          analyticsIngest: { ran = true })

        let did = await coordinator.maybeRunAnalyticsIngest()

        XCTAssertTrue(did)
        XCTAssertTrue(ran)
    }
}
