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
}
