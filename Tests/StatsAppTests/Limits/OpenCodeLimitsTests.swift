import XCTest
@testable import StatsApp

final class OpenCodeUsageParserTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    // Страница приходит в формате React Flight — не HTML и не JSON, поэтому
    // достаём брейс-сбалансированные блоки, а не парсим целиком.
    private let page = """
    $R[3]={rollingUsage:{usagePercent:0,resetInSec:1200,limit:{usagePercent:99}},\
    weeklyUsage:{usagePercent:2.5,resetInSec:200000},\
    monthlyUsage:{usagePercent:31,resetInSec:2000000}}
    """

    func test_parses_three_windows() throws {
        let windows = try XCTUnwrap(OpenCodeUsageParser.parseLimits(page, now: now))
            .sorted { $0.windowMinutes < $1.windowMinutes }
        XCTAssertEqual(windows.map(\.windowMinutes), [300, 10080, 43200])
        XCTAssertEqual(windows[0].usedPercent, 0)
        XCTAssertEqual(windows[1].usedPercent, 2.5)
        XCTAssertEqual(windows[2].usedPercent, 31)
        XCTAssertEqual(windows[0].resetsAt, now.addingTimeInterval(1200))
    }

    // Вложенный usagePercent внутри limit:{...} не должен победить внешний.
    func test_ignores_nested_usage_percent() throws {
        let windows = try XCTUnwrap(OpenCodeUsageParser.parseLimits(page, now: now))
        let rolling = try XCTUnwrap(windows.first { $0.windowMinutes == 300 })
        XCTAssertEqual(rolling.usedPercent, 0)
    }

    // Месячного окна может не быть — это не повод терять два остальных.
    func test_monthly_null_still_returns_two_windows() throws {
        let text = "rollingUsage:{usagePercent:1,resetInSec:10},weeklyUsage:{usagePercent:2,resetInSec:20},monthlyUsage:null"
        let windows = try XCTUnwrap(OpenCodeUsageParser.parseLimits(text, now: now))
        XCTAssertEqual(windows.count, 2)
    }

    // Без rolling и weekly считаем, что вёрстка поменялась — отдаём nil, а не пусто.
    func test_nil_when_required_windows_missing() {
        XCTAssertNil(OpenCodeUsageParser.parseLimits("совсем не та страница", now: now))
        XCTAssertNil(OpenCodeUsageParser.parseLimits("rollingUsage:{usagePercent:1,resetInSec:10}", now: now))
    }

    func test_parses_workspace_ids_in_order_without_duplicates() {
        let text = #"{id:"wrk_AAA",name:"x"},{id:"wrk_BBB"},{id:"wrk_AAA"}"#
        XCTAssertEqual(OpenCodeUsageParser.parseWorkspaceIDs(text), ["wrk_AAA", "wrk_BBB"])
    }

    func test_normalizes_bare_cookie_token() {
        XCTAssertEqual(OpenCodeUsageParser.normalizeCookie("Fe26.2**abc"), "auth=Fe26.2**abc")
        XCTAssertEqual(OpenCodeUsageParser.normalizeCookie("auth=Fe26.2**abc"), "auth=Fe26.2**abc")
        XCTAssertEqual(OpenCodeUsageParser.normalizeCookie("  "), "")
    }

    // На opencode.ai уходит только auth-кука: чужие сессии из вставленной строки
    // отправлять нельзя.
    func test_filters_out_foreign_cookies() {
        let raw = "ga=123; auth=Fe26.2**abc; __Host-auth=zzz; tracker=nope"
        XCTAssertEqual(OpenCodeUsageParser.filterAuthCookie(raw),
                       "auth=Fe26.2**abc; __Host-auth=zzz")
    }

    // normalizeCookie принимает "Auth=" регистронезависимо (проверяет через
    // .lowercased()), но раньше filterAuthCookie сравнивал имя строго — такая
    // cookie сохранялась и тут же вырезалась в ноль при каждом запросе, вечный
    // unconfigured при заполненном поле (находка 10 финального ревью).
    func test_filters_auth_cookie_case_insensitively() {
        let raw = "Auth=Fe26.2**abc; __Host-Auth=zzz"
        XCTAssertEqual(OpenCodeUsageParser.filterAuthCookie(raw),
                       "Auth=Fe26.2**abc; __Host-Auth=zzz")
    }
}

final class OpenCodeLimitsFetcherTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func fetcher(cookie: String?) -> OpenCodeLimitsFetcher {
        let store = MemoryKeychainStore()
        if let cookie {
            try? store.set(cookie, account: "tester",
                           service: OpenCodeLimitsFetcher.keychainService)
        }
        return OpenCodeLimitsFetcher(keychain: store, account: "tester",
                                     session: StubURLProtocol.session(),
                                     now: { Date(timeIntervalSince1970: 1_785_000_000) })
    }

    private func ok(_ url: URL, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
         Data(body.utf8))
    }

    func test_discovers_workspace_then_parses_limits() async {
        StubURLProtocol.handler = { request in
            let url = request.url!
            if url.path == "/_server" {
                return self.ok(url, #"{id:"wrk_ABC"}"#)
            }
            return self.ok(url, "rollingUsage:{usagePercent:0,resetInSec:1200},weeklyUsage:{usagePercent:2,resetInSec:200000}")
        }
        let limits = await fetcher(cookie: "Fe26.2**abc").fetch()
        XCTAssertEqual(limits.status, .ok)
        XCTAssertEqual(limits.windows.count, 2)
    }

    func test_no_cookie_is_unconfigured_and_never_hits_network() async {
        StubURLProtocol.handler = { _ in XCTFail("сети быть не должно"); return (HTTPURLResponse(), Data()) }
        let limits = await fetcher(cookie: nil).fetch()
        XCTAssertEqual(limits.status, .unconfigured)
    }

    func test_no_workspace_is_unauthorized() async {
        StubURLProtocol.handler = { request in self.ok(request.url!, "пусто") }
        let limits = await fetcher(cookie: "Fe26.2**abc").fetch()
        XCTAssertEqual(limits.status, .unauthorized)
    }

    // Вёрстка поменялась: воркспейс нашёлся, а usage не разобрался.
    func test_unparsable_page_is_unavailable() async {
        StubURLProtocol.handler = { request in
            request.url!.path == "/_server"
                ? self.ok(request.url!, #"{id:"wrk_ABC"}"#)
                : self.ok(request.url!, "<html>редизайн</html>")
        }
        let limits = await fetcher(cookie: "Fe26.2**abc").fetch()
        XCTAssertEqual(limits.status, .unavailable)
    }

    // Непонятный HTTP-код — единственный сигнал, по которому можно отличить
    // протухший захардкоженный workspacesServerID от редизайна страницы.
    // Generic-сообщение Foundation ("The operation couldn't be completed…")
    // для этого бесполезно (находка 11 финального ревью).
    func test_unexpected_status_reports_code_in_error_message() async {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
             Data())
        }
        let limits = await fetcher(cookie: "Fe26.2**abc").fetch()
        XCTAssertEqual(limits.status, .stale)
        XCTAssertEqual(limits.error, "HTTP 500 от opencode.ai")
    }

    // Секретная cookie не должна оседать в системном cookie storage мимо
    // Keychain, и вручную выставленный заголовок Cookie не должен
    // подмешиваться с чужими куками системы (находка 7 финального ревью).
    func test_default_session_disables_shared_cookie_storage() {
        let config = URLSession.limitsFetching().configuration
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertNil(config.httpCookieStorage)
    }
}
