import XCTest
import GRDB
@testable import StatsApp

final class SyncCoordinatorSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Удаляем snapshot с прошлого теста, чтобы не читать чужие данные.
        try? FileManager.default.removeItem(at: WidgetSnapshotIO.writeURL)
    }

    // MARK: - Helpers

    /// Читает snapshot из writeURL (именно туда пишет SyncCoordinator).
    private func readSnapshot() throws -> WidgetSnapshot {
        let data = try Data(contentsOf: WidgetSnapshotIO.writeURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }

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

        // Триггерим запись snapshot'а через runOnce с пустым фетчером (всё уже в DB).
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let snapshot = try readSnapshot()
        XCTAssertEqual(snapshot.day.aiCost, 250.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.day.aiCostPrev, 222.40, accuracy: 0.001)
    }

    /// Если в leaderboard_cache есть payload — top-N попадает в slice; если меня нет в топе, я в meBelow.
    func test_snapshot_day_slice_contains_leaderboard_top8_and_meBelow() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        try await dbq.write { db in
            // Свой профиль — нужен для myFriendCode и meBelow.
            try StatsQueries.saveMyProfile(db, MyProfileRow(
                friendCode: "me123", displayName: "Я", avatarPath: nil, sharingEnabled: true, serverUserId: 1
            ))
            // Лидерборд: 10 человек, я — 9-й.
            let payload = """
            {
              "period": "day",
              "as_of": "2026-05-23T12:00:00Z",
              "entries": [
                {"friend_code":"u1","display_name":"A","rank":1,"previous_rank":2,"tokens_total":1000,"is_me":false},
                {"friend_code":"u2","display_name":"B","rank":2,"previous_rank":1,"tokens_total":900, "is_me":false},
                {"friend_code":"u3","display_name":"C","rank":3,"previous_rank":null,"tokens_total":800,"is_me":false},
                {"friend_code":"u4","display_name":"D","rank":4,"previous_rank":4,"tokens_total":700, "is_me":false},
                {"friend_code":"u5","display_name":"E","rank":5,"previous_rank":3,"tokens_total":600, "is_me":false},
                {"friend_code":"u6","display_name":"F","rank":6,"previous_rank":6,"tokens_total":500, "is_me":false},
                {"friend_code":"u7","display_name":"G","rank":7,"previous_rank":8,"tokens_total":400, "is_me":false},
                {"friend_code":"u8","display_name":"H","rank":8,"previous_rank":7,"tokens_total":300, "is_me":false},
                {"friend_code":"me123","display_name":"Я","rank":9,"previous_rank":12,"tokens_total":200,"is_me":true},
                {"friend_code":"u10","display_name":"J","rank":10,"previous_rank":null,"tokens_total":100,"is_me":false}
              ]
            }
            """
            try StatsQueries.saveLeaderboardCache(db, period: "day", payloadJson: payload)
        }

        let now = Date(timeIntervalSince1970: 1_779_873_600)
        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let snapshot = try readSnapshot()
        XCTAssertEqual(snapshot.myFriendCode, "me123")
        let lb = snapshot.day.leaderboard
        XCTAssertNotNil(lb)
        XCTAssertEqual(lb!.entries.count, 8)
        XCTAssertEqual(lb!.entries.first?.rank, 1)
        XCTAssertEqual(lb!.entries.last?.rank, 8)
        // Я — 9-й, в топ-8 не попал, должен быть в meBelow.
        XCTAssertNotNil(lb!.meBelow)
        XCTAssertEqual(lb!.meBelow?.rank, 9)
        XCTAssertEqual(lb!.meBelow?.isMe, true)
    }

    /// Если меня нет в кэше вообще — meBelow = nil.
    func test_snapshot_leaderboard_meBelow_nil_when_me_absent() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        try await dbq.write { db in
            try StatsQueries.saveMyProfile(db, MyProfileRow(
                friendCode: "ghost", displayName: "?", avatarPath: nil, sharingEnabled: true, serverUserId: 1
            ))
            let payload = """
            {"period":"day","as_of":"2026-05-23T12:00:00Z","entries":[
              {"friend_code":"u1","display_name":"A","rank":1,"previous_rank":null,"tokens_total":1000,"is_me":false}
            ]}
            """
            try StatsQueries.saveLeaderboardCache(db, period: "day", payloadJson: payload)
        }

        let now = Date(timeIntervalSince1970: 1_779_873_600)
        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let lb = try readSnapshot().day.leaderboard!
        XCTAssertEqual(lb.entries.count, 1)
        XCTAssertNil(lb.meBelow)
    }

    /// Если кэша лидерборда нет — leaderboard = nil.
    func test_snapshot_leaderboard_nil_when_no_cache() async throws {
        let dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        let now = Date(timeIntervalSince1970: 1_779_873_600)
        let coordinator = await SyncCoordinator(db: dbq, now: { now })
        let fetcher = await MockFetcher(result: .aiUsage(CcusagePayload(dayRows: [], modelRows: [])))
        try await coordinator.runOnce(source: "ccusage", fetchers: [fetcher])

        let snapshot = try readSnapshot()
        XCTAssertNil(snapshot.day.leaderboard)
        XCTAssertNil(snapshot.myFriendCode)
    }
}

// Локальный MockFetcher — копия из SyncCoordinatorTests (намеренно дублируем, файлы тестов независимы).
private actor MockFetcher: Fetcher {
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
