import XCTest
@testable import StatsApp

final class ClaudeUsageParserTests: XCTestCase {

    // Форма ответа /api/oauth/usage, проверена живьём 2026-07-31.
    func test_parses_five_hour_and_seven_day() {
        let data = Data(#"""
        {"five_hour":{"utilization":75,"resets_at":"2026-07-31T15:30:00Z"},
         "seven_day":{"utilization":51.4,"resets_at":"2026-08-04T02:00:00Z"}}
        """#.utf8)

        let windows = ClaudeUsageParser.parse(data).sorted { $0.windowMinutes < $1.windowMinutes }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].windowMinutes, 300)
        XCTAssertEqual(windows[0].usedPercent, 75)
        XCTAssertEqual(windows[1].windowMinutes, 10080)
        XCTAssertEqual(windows[1].usedPercent, 51.4)
        XCTAssertNotNil(windows[0].resetsAt)
    }

    // Живой ответ эндпоинта отдаёт время сброса с дробными секундами — снято
    // 2026-07-31 с рабочего токена. Дефолтный ISO8601DateFormatter такое не
    // разбирает, и resetsAt молча становился nil: строка «сброс через N» у
    // Claude не показывалась никогда, а выбор окна для кольца сваливался
    // в запасную ветку «самое короткое по длительности».
    func test_parses_reset_time_with_fractional_seconds() throws {
        let data = Data(#"""
        {"five_hour":{"utilization":31,"resets_at":"2026-07-31T18:30:00.602320+00:00"},
         "seven_day":{"utilization":14,"resets_at":"2026-08-06T06:00:00.602340+00:00"}}
        """#.utf8)

        let windows = ClaudeUsageParser.parse(data).sorted { $0.windowMinutes < $1.windowMinutes }
        XCTAssertEqual(windows.count, 2)

        let fiveHour = try XCTUnwrap(windows[0].resetsAt)
        XCTAssertEqual(fiveHour.timeIntervalSince1970, 1_785_522_600, accuracy: 1)

        let sevenDay = try XCTUnwrap(windows[1].resetsAt)
        XCTAssertEqual(sevenDay.timeIntervalSince1970, 1_785_996_000, accuracy: 1)
    }

    // Форма без дробей обязана продолжать работать — эндпоинт недокументирован,
    // формат может отличаться между окнами или поменяться обратно.
    func test_still_parses_reset_time_without_fractional_seconds() throws {
        let data = Data(#"{"five_hour":{"utilization":10,"resets_at":"2026-07-31T15:30:00Z"}}"#.utf8)
        let reset = try XCTUnwrap(ClaudeUsageParser.parse(data).first?.resetsAt)
        XCTAssertEqual(reset.timeIntervalSince1970, 1_785_511_800, accuracy: 1)
    }

    func test_skips_window_without_utilization() {
        let data = Data(#"{"five_hour":{"resets_at":"2026-07-31T15:30:00Z"},"seven_day":null}"#.utf8)
        XCTAssertTrue(ClaudeUsageParser.parse(data).isEmpty)
    }

    func test_keeps_window_without_reset_time() {
        let data = Data(#"{"seven_day":{"utilization":10}}"#.utf8)
        let windows = ClaudeUsageParser.parse(data)
        XCTAssertEqual(windows.count, 1)
        XCTAssertNil(windows[0].resetsAt)
    }

    func test_returns_empty_on_garbage() {
        XCTAssertTrue(ClaudeUsageParser.parse(Data("не json".utf8)).isEmpty)
    }

    func test_extracts_token_from_keychain_blob() {
        let blob = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat-XXX","expiresAt":123}}"#
        XCTAssertEqual(ClaudeUsageParser.tokenFromKeychainBlob(blob), "sk-ant-oat-XXX")
    }

    func test_token_nil_when_blob_has_no_oauth() {
        XCTAssertNil(ClaudeUsageParser.tokenFromKeychainBlob(#"{"mcpOAuth":{}}"#))
        XCTAssertNil(ClaudeUsageParser.tokenFromKeychainBlob("мусор"))
        XCTAssertNil(ClaudeUsageParser.tokenFromKeychainBlob(#"{"claudeAiOauth":{"accessToken":""}}"#))
    }

    // Живой 429 отдал Retry-After: 3582 — почти час. Секунды, не дата.
    func test_retry_after_seconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let at = ClaudeLimitsFetcher.retryAfterDate(from: "3582", now: now)
        XCTAssertEqual(at, Date(timeIntervalSince1970: 1_003_582))
    }

    func test_retry_after_missing_defaults_to_an_hour() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ClaudeLimitsFetcher.retryAfterDate(from: nil, now: now),
                       Date(timeIntervalSince1970: 1_003_600))
    }
}

/// URLProtocol-стаб: живой сети в тестах нет.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

final class ClaudeLimitsFetcherTests: XCTestCase {

    private let blob = #"{"claudeAiOauth":{"accessToken":"tok"}}"#

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func fetcher(keychainValue: String?) -> ClaudeLimitsFetcher {
        let store = MemoryKeychainStore()
        if let keychainValue {
            try? store.set(keychainValue, account: "tester",
                           service: ClaudeLimitsFetcher.keychainService)
        }
        return ClaudeLimitsFetcher(keychain: store, account: "tester",
                                   session: StubURLProtocol.session(),
                                   now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    private func response(_ code: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
                        statusCode: code, httpVersion: nil, headerFields: headers)!
    }

    func test_ok_returns_windows() async {
        StubURLProtocol.handler = { _ in
            (self.response(200), Data(#"{"five_hour":{"utilization":75},"seven_day":{"utilization":51}}"#.utf8))
        }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .ok)
        XCTAssertEqual(limits.windows.count, 2)
        XCTAssertEqual(limits.fetchedAt, Date(timeIntervalSince1970: 1_000_000))
    }

    func test_missing_token_is_unauthorized_and_never_hits_network() async {
        StubURLProtocol.handler = { _ in XCTFail("сети быть не должно"); return (self.response(200), Data()) }
        let limits = await fetcher(keychainValue: nil).fetch()
        XCTAssertEqual(limits.status, .unauthorized)
        XCTAssertTrue(limits.windows.isEmpty)
    }

    func test_401_is_unauthorized() async {
        StubURLProtocol.handler = { _ in (self.response(401), Data()) }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .unauthorized)
    }

    func test_429_sets_retry_after_and_reports_throttled() async {
        StubURLProtocol.handler = { _ in
            (self.response(429, headers: ["Retry-After": "3582"]),
             Data(#"{"error":{"type":"rate_limit_error"}}"#.utf8))
        }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .throttled)
        XCTAssertEqual(limits.retryAfter, Date(timeIntervalSince1970: 1_003_582))
    }

    // 200 с неизвестной формой — это «эндпоинт поменялся», а не «лимитов ноль».
    func test_200_with_unknown_shape_is_unavailable_not_zero() async {
        StubURLProtocol.handler = { _ in (self.response(200), Data(#"{"foo":1}"#.utf8)) }
        let limits = await fetcher(keychainValue: blob).fetch()
        XCTAssertEqual(limits.status, .unavailable)
        XCTAssertTrue(limits.windows.isEmpty)
    }
}
