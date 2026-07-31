import XCTest
import GRDB
@testable import StatsApp

final class LimitsRepositoryTests: XCTestCase {

    private func makeDB() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)
        return queue
    }

    private func limits(_ pct: Double, reset: TimeInterval?, status: LimitStatus = .ok) -> ProviderLimits {
        ProviderLimits(provider: .codex,
                       windows: [LimitWindow(windowMinutes: 10080, usedPercent: pct,
                                             resetsAt: reset.map { Date(timeIntervalSince1970: $0) })],
                       status: status, fetchedAt: Date(timeIntervalSince1970: 1_000), error: nil)
    }

    // Ровный опрос раз в 5 минут не должен плодить одинаковые строки — второму
    // этапу нужны ступени, а не пила из идентичных значений.
    func test_identical_snapshot_is_not_written_twice() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)
    }

    func test_changed_percent_is_written() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(79, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 2)
    }

    // Сброс окна: процент упал, время сброса уехало — это новая ступень.
    func test_changed_reset_time_is_written() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(78, reset: 1_786_510_162), now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 2)
    }

    // Неудачный опрос не имеет права затирать последние известные цифры.
    func test_failed_fetch_does_not_write_snapshot_but_updates_state() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(ProviderLimits.failure(.codex, status: .stale, error: "сеть"),
                              now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)

        let state = try await db.read { try LimitFetchStateRow.fetchAll($0) }
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state[0].status, "stale")
        XCTAssertEqual(state[0].lastSuccessAt, 1_000)
        XCTAssertEqual(state[0].lastAttemptAt, 1_300)
    }

    // Последнее состояние: цифры из snapshots, статус из state.
    func test_latest_merges_snapshots_with_state() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(ProviderLimits.failure(.codex, status: .stale, error: "сеть"),
                              now: Date(timeIntervalSince1970: 1_300))

        let latest = try await repo.latest()
        let codex = try XCTUnwrap(latest[.codex])
        XCTAssertEqual(codex.status, .stale)
        XCTAssertEqual(codex.windows.count, 1)
        XCTAssertEqual(codex.windows[0].usedPercent, 78)
        XCTAssertEqual(codex.fetchedAt, Date(timeIntervalSince1970: 1_000))
    }

    func test_latest_returns_only_newest_row_per_window() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(10, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.record(limits(20, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 2_000))

        let latest = try await repo.latest()
        let codex = try XCTUnwrap(latest[.codex])
        XCTAssertEqual(codex.windows.count, 1)
        XCTAssertEqual(codex.windows[0].usedPercent, 20)
    }

    // Путь 429: saveState фиксирует throttled + retry_after, не трогая ни
    // историю, ни lastSuccessAt — координатор не имеет права выдавать это
    // за успешный опрос.
    func test_save_state_records_throttle_without_touching_history_or_last_success() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.record(limits(78, reset: 1_785_905_362), now: Date(timeIntervalSince1970: 1_000))
        try await repo.saveState(provider: .codex, status: .throttled, error: "429",
                                 retryAfter: Date(timeIntervalSince1970: 1_600),
                                 now: Date(timeIntervalSince1970: 1_300))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)

        let state = try await db.read { try LimitFetchStateRow.fetchAll($0) }
        XCTAssertEqual(state.count, 1)
        XCTAssertEqual(state[0].status, "throttled")
        XCTAssertEqual(state[0].retryAfterAt, 1_600)
        XCTAssertEqual(state[0].lastSuccessAt, 1_000)
        XCTAssertEqual(state[0].lastAttemptAt, 1_300)
    }

    // latest() обязан дочитывать retry_after_at — без этого попап не может
    // показать «следующая попытка через …» для throttled (см. финальный ревью).
    func test_latest_includes_retry_after_for_throttled_provider() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.saveState(provider: .claude, status: .throttled, error: "429",
                                 retryAfter: Date(timeIntervalSince1970: 5_000),
                                 now: Date(timeIntervalSince1970: 1_000))

        let latest = try await repo.latest()
        let claude = try XCTUnwrap(latest[.claude])
        XCTAssertEqual(claude.retryAfter, Date(timeIntervalSince1970: 5_000))
    }

    // Координатору после перезапуска нужен способ прочитать все состояния разом,
    // чтобы восстановить lastAttempt/retryAfter — без чтения он не узнает,
    // что окно троттлинга ещё не истекло.
    func test_fetch_states_returns_all_persisted_rows() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)

        try await repo.saveState(provider: .claude, status: .throttled, error: "429",
                                 retryAfter: Date(timeIntervalSince1970: 5_000),
                                 now: Date(timeIntervalSince1970: 1_000))

        let states = try await repo.fetchStates()
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].provider, "claude")
        XCTAssertEqual(states[0].retryAfterAt, 5_000)
        XCTAssertEqual(states[0].lastAttemptAt, 1_000)
    }

    func test_prune_drops_snapshots_older_than_retention() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db, retentionDays: 60)

        try await db.write { db in
            var old = LimitSnapshotRow(id: nil, provider: "codex", windowMinutes: 10080,
                                       usedPercent: 5, resetsAt: nil, observedAt: 0)
            try old.insert(db)
        }
        try await repo.record(limits(78, reset: nil), now: Date(timeIntervalSince1970: 61 * 86_400))
        try await repo.pruneOldSnapshots(now: Date(timeIntervalSince1970: 61 * 86_400))

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].usedPercent, 78)
    }
}
