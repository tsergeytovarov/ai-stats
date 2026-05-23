import XCTest
import GRDB
@testable import StatsApp

final class SnapshotSyncerTests: XCTestCase {
    var db: DatabaseQueue!
    var apiCalls: [SnapshotItem] = []
    var apiResponse: Result<SnapshotsResponse, Error> = .success(SnapshotsResponse(accepted: 0))

    override func setUp() async throws {
        try await super.setUp()
        db = try DatabaseQueue()
        try Database.migrate(db)
        apiCalls = []
        apiResponse = .success(SnapshotsResponse(accepted: 0))
        MockURLProtocol.responder = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.lastBody = nil
    }

    @MainActor
    private func makeSyncer() -> SnapshotSyncer {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let captureCalls: (URLRequest) throws -> (HTTPURLResponse, Data) = { [weak self] req in
            guard let self else {
                throw URLError(.cancelled)
            }
            if let body = req.httpBody ?? req.bodyStreamData(),
               let batch = try? JSONDecoder().decode(SnapshotsBatch.self, from: body) {
                self.apiCalls.append(contentsOf: batch.snapshots)
            }
            switch self.apiResponse {
            case .success(let resp):
                let http = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                let data = try JSONEncoder().encode(resp)
                return (http, data)
            case .failure(let err):
                throw err
            }
        }
        MockURLProtocol.responder = captureCalls

        let api = AiuseAPIClient(
            baseURL: URL(string: "https://test.local/api")!,
            secretProvider: { "secret" },
            session: session
        )
        // now=2026-05-23 12:00 UTC = 1747958400 + (some offset). Делаем фиксированной точкой для всех тестов.
        return SnapshotSyncer(
            db: db,
            api: api,
            now: { Date(timeIntervalSince1970: 1779840000) }   // 2026-05-27 00:00:00 UTC
        )
    }

    /// helper для вставки фиктивной usage-записи (ai_usage с UNIQUE day,source)
    private func insertUsage(day: String, input: Int64, output: Int64, source: String = "claude") throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO ai_usage (day, source, models_json, input_tokens, output_tokens, cost_usd, updated_at)
                VALUES (?, ?, '[]', ?, ?, 0.0, '2026-05-23T00:00:00Z')
                """, arguments: [day, source, input, output])
        }
    }

    /// helper для вставки my_profile
    private func insertMyProfile(sharingEnabled: Bool = true) throws {
        try db.write { db in
            let p = MyProfileRow(
                id: 1, friendCode: "TESTCODE12",
                displayName: "Test", avatarPath: nil,
                sharingEnabled: sharingEnabled, serverUserId: 1
            )
            try p.save(db)
        }
    }

    // MARK: - Tests

    @MainActor
    func testNoProfile_skipsSync() async throws {
        try insertUsage(day: "2026-05-22", input: 100, output: 200)
        let syncer = makeSyncer()
        let accepted = try await syncer.runOnce()
        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(apiCalls.count, 0, "should not call API without profile")
    }

    @MainActor
    func testSharingDisabled_skipsSync() async throws {
        try insertMyProfile(sharingEnabled: false)
        try insertUsage(day: "2026-05-22", input: 100, output: 200)
        let syncer = makeSyncer()
        let accepted = try await syncer.runOnce()
        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(apiCalls.count, 0)
    }

    @MainActor
    func testHappyPath_sendsDailySnapshots() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-25", input: 100, output: 200)
        try insertUsage(day: "2026-05-26", input: 50, output: 80)
        apiResponse = .success(SnapshotsResponse(accepted: 2))

        let syncer = makeSyncer()
        let accepted = try await syncer.runOnce()

        XCTAssertEqual(accepted, 2)
        XCTAssertEqual(apiCalls.count, 2)
        let buckets = Set(apiCalls.map { $0.hourBucket })
        XCTAssertTrue(buckets.contains("2026-05-25T00:00:00Z"))
        XCTAssertTrue(buckets.contains("2026-05-26T00:00:00Z"))

        // После успеха pending должен быть пуст
        let remaining = try await db.read { try StatsQueries.loadReadyPendingSnapshots($0) }
        XCTAssertEqual(remaining.count, 0)
    }

    @MainActor
    func testMultipleProvidersSummed() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-25", input: 100, output: 200, source: "claude")
        try insertUsage(day: "2026-05-25", input: 10, output: 20, source: "codex")
        apiResponse = .success(SnapshotsResponse(accepted: 1))

        let syncer = makeSyncer()
        _ = try await syncer.runOnce()

        XCTAssertEqual(apiCalls.count, 1)
        XCTAssertEqual(apiCalls.first?.tokensInput, 110)
        XCTAssertEqual(apiCalls.first?.tokensOutput, 220)
    }

    @MainActor
    func testApiFailure_incrementsAttempts() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-25", input: 100, output: 200)
        apiResponse = .failure(AiuseAPIError.http(status: 500, body: "boom"))

        let syncer = makeSyncer()
        do {
            _ = try await syncer.runOnce()
            XCTFail("expected error")
        } catch {
            // OK
        }

        let pending = try await db.read { try StatsQueries.loadReadyPendingSnapshots($0) }
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.attempts, 1)
        XCTAssertNotNil(pending.first?.lastError)
    }

    @MainActor
    func testRetryAfterFailure_succeeds() async throws {
        try insertMyProfile()
        try insertUsage(day: "2026-05-25", input: 100, output: 200)

        let syncer = makeSyncer()

        // 1-й call: fail
        apiResponse = .failure(AiuseAPIError.http(status: 503, body: ""))
        _ = try? await syncer.runOnce()

        // 2-й call: success
        apiResponse = .success(SnapshotsResponse(accepted: 1))
        let accepted = try await syncer.runOnce()
        XCTAssertEqual(accepted, 1)

        // pending очищен
        let remaining = try await db.read { try StatsQueries.loadReadyPendingSnapshots($0) }
        XCTAssertEqual(remaining.count, 0)
    }
}
