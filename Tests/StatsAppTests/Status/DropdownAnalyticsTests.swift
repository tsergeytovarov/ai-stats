import XCTest
import GRDB
@testable import StatsApp

@MainActor
final class DropdownAnalyticsTests: XCTestCase {

    /// VM.loadAnalytics читает карточку из сид-БД и публикует её в analyticsCard.
    func test_loadAnalytics_populates_card_from_seeded_db() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        // Сид: 60 codex-ходов роли-пайплайна (кластер «ты — …») за сегодня —
        // окно 30 дней ловит их независимо от даты прогона теста.
        let today = DateUtils.isoDayLocal(Date())
        try await dbq.write { db in
            for i in 0..<60 {
                var row = AnalyticsTurnRow(
                    id: nil, source: "codex", ts: "\(today)T10:00:00Z-\(i)",
                    day: today, session: "s\(i)", project: "/p", model: "gpt-5.5",
                    origin: "human", promptHead: "ты — рерайтер роль x", promptChars: 20,
                    nRequests: 1, inputTokens: 1000, outputTokens: 0,
                    costUsd: 5.0, expSavedUsd: 0.5
                )
                try row.insert(db)
            }
        }

        let coordinator = SyncCoordinator(db: dbq)
        let vm = DropdownViewModel(db: dbq, syncCoordinator: coordinator)

        await vm.loadAnalytics()

        let card = try XCTUnwrap(vm.analyticsCard)
        XCTAssertEqual(card.state, .ready)
        XCTAssertEqual(card.topLeakTitle, "Регулярная роль: Рерайтер роль x")
        XCTAssertEqual(card.sources.first?.source, "codex")
        XCTAssertNotNil(vm.modelGuide)
    }

    /// Пустая БД → состояние «нет данных».
    func test_loadAnalytics_no_data() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        let coordinator = SyncCoordinator(db: dbq)
        let vm = DropdownViewModel(db: dbq, syncCoordinator: coordinator)

        await vm.loadAnalytics()

        XCTAssertEqual(vm.analyticsCard?.state, .noData)
    }
}
