import XCTest
import GRDB
@testable import StatsApp

/// Фейковый источник: считает вызовы и отдаёт заранее заданный результат.
final class FakeLimitsFetcher: LimitsFetching, @unchecked Sendable {
    let provider: LimitProvider
    private(set) var calls = 0
    var result: ProviderLimits

    init(provider: LimitProvider, result: ProviderLimits) {
        self.provider = provider
        self.result = result
    }

    func fetch() async -> ProviderLimits {
        calls += 1
        return result
    }
}

final class LimitsCoordinatorTests: XCTestCase {

    private func makeDB() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrate(queue)
        return queue
    }

    private func ok(_ provider: LimitProvider, pct: Double) -> ProviderLimits {
        ProviderLimits(provider: provider,
                       windows: [LimitWindow(windowMinutes: 10080, usedPercent: pct, resetsAt: nil)],
                       status: .ok, fetchedAt: Date(timeIntervalSince1970: 0), error: nil)
    }

    func test_first_tick_polls_every_provider() async throws {
        let db = try makeDB()
        let fetchers = LimitProvider.allCases.map { FakeLimitsFetcher(provider: $0, result: ok($0, pct: 10)) }
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = LimitsCoordinator(fetchers: fetchers,
                                            repository: LimitsRepository(db: db),
                                            now: { clock })

        await coordinator.tick()
        XCTAssertEqual(fetchers.map(\.calls), [1, 1, 1])
        _ = clock
    }

    // Каждый источник со своим расписанием: через 6 минут Codex опрашивается
    // снова, а Claude с его часовым троттлингом — нет.
    func test_respects_per_provider_intervals() async throws {
        let db = try makeDB()
        let codex = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 10))
        let claude = FakeLimitsFetcher(provider: .claude, result: ok(.claude, pct: 20))
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = LimitsCoordinator(fetchers: [codex, claude],
                                            repository: LimitsRepository(db: db),
                                            now: { clock })

        await coordinator.tick()
        clock = clock.addingTimeInterval(360)   // +6 минут
        await coordinator.tick()

        XCTAssertEqual(codex.calls, 2)
        XCTAssertEqual(claude.calls, 1)
    }

    // 429 у Claude: Retry-After перебивает расписание. Ставим его на два часа —
    // по часовому интервалу мы бы уже сходили, а по Retry-After ещё нельзя.
    func test_throttled_provider_is_not_polled_until_retry_after() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let claude = FakeLimitsFetcher(
            provider: .claude,
            result: .failure(.claude, status: .throttled, error: "429",
                             retryAfter: start.addingTimeInterval(7_200)))
        var clock = start
        let coordinator = LimitsCoordinator(fetchers: [claude], repository: repo, now: { clock })

        await coordinator.tick()
        XCTAssertEqual(claude.calls, 1)

        // +70 минут: часовой интервал истёк, но Retry-After — нет.
        clock = start.addingTimeInterval(4_200)
        await coordinator.tick()
        XCTAssertEqual(claude.calls, 1)

        // +2 часа с минутой: Retry-After истёк, можно снова.
        clock = start.addingTimeInterval(7_260)
        await coordinator.tick()
        XCTAssertEqual(claude.calls, 2)
    }

    // Перезапуск приложения внутри окна троттлинга: retry_after_at из прошлого
    // запуска ещё в будущем, значит первый же тик не имеет права опрашивать
    // claude заново — иначе это долбёжка в заведомо закрытую дверь (находка 2
    // финального ревью: retry_after_at писался, но никогда не перечитывался).
    func test_first_tick_after_restart_respects_persisted_retry_after() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)
        let start = Date(timeIntervalSince1970: 1_000_000)

        // Предыдущий запуск оставил claude throttled с retry_after в будущем
        // относительно текущего start.
        try await repo.saveState(provider: .claude, status: .throttled, error: "429",
                                 retryAfter: start.addingTimeInterval(1_800),
                                 now: start.addingTimeInterval(-10))

        let claude = FakeLimitsFetcher(provider: .claude, result: ok(.claude, pct: 5))
        let coordinator = LimitsCoordinator(fetchers: [claude], repository: repo, now: { start })

        await coordinator.tick()

        XCTAssertEqual(claude.calls, 0)
    }

    // lastAttempt тоже должен восстанавливаться: иначе после перезапуска
    // приложение опросит всех, даже тех, кого только что опрашивали за минуту
    // до рестарта — интервал не должен занулиться просто потому что процесс
    // перезапустился.
    func test_first_tick_after_restart_respects_persisted_last_attempt() async throws {
        let db = try makeDB()
        let repo = LimitsRepository(db: db)
        let start = Date(timeIntervalSince1970: 1_000_000)

        // Codex опрашивался минуту назад в прошлом запуске — 5-минутный
        // интервал ещё не истёк.
        try await repo.record(ok(.codex, pct: 5), now: start.addingTimeInterval(-60))

        let codex = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 10))
        let coordinator = LimitsCoordinator(fetchers: [codex], repository: repo, now: { start })

        await coordinator.tick()

        XCTAssertEqual(codex.calls, 0)
    }

    func test_tick_writes_snapshots() async throws {
        let db = try makeDB()
        let codex = FakeLimitsFetcher(provider: .codex, result: ok(.codex, pct: 78))
        let coordinator = LimitsCoordinator(fetchers: [codex],
                                            repository: LimitsRepository(db: db),
                                            now: { Date(timeIntervalSince1970: 1_000_000) })

        await coordinator.tick()

        let rows = try await db.read { try LimitSnapshotRow.fetchAll($0) }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].usedPercent, 78)
    }
}
