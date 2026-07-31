import XCTest
@testable import StatsApp

final class LimitFormatTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    func test_percent_without_pointless_decimals() {
        XCTAssertEqual(LimitFormat.percent(78), "78%")
        XCTAssertEqual(LimitFormat.percent(2.5), "2.5%")
        XCTAssertEqual(LimitFormat.percent(0), "0%")
        XCTAssertEqual(LimitFormat.percent(51.04), "51%")
    }

    func test_window_titles() {
        XCTAssertEqual(LimitFormat.window(minutes: 300), "5 часов")
        XCTAssertEqual(LimitFormat.window(minutes: 10080), "неделя")
        XCTAssertEqual(LimitFormat.window(minutes: 43200), "месяц")
        XCTAssertEqual(LimitFormat.window(minutes: 1440), "24 часа")
    }

    func test_resets_in_human_text() {
        XCTAssertEqual(LimitFormat.resetsIn(now.addingTimeInterval(90 * 60), now: now),
                       "сброс через 1ч 30м")
        XCTAssertEqual(LimitFormat.resetsIn(now.addingTimeInterval(40 * 60), now: now),
                       "сброс через 40м")
        XCTAssertEqual(LimitFormat.resetsIn(now.addingTimeInterval(50 * 3600), now: now),
                       "сброс через 2д 2ч")
        XCTAssertNil(LimitFormat.resetsIn(nil, now: now))
        // Время сброса в прошлом — окно уже должно было сброситься, врать не будем.
        XCTAssertNil(LimitFormat.resetsIn(now.addingTimeInterval(-60), now: now))
    }

    func test_action_text_only_for_states_needing_the_user() {
        XCTAssertEqual(LimitFormat.actionText(for: .claude, status: .unauthorized),
                       "Claude: нужен вход заново")
        XCTAssertEqual(LimitFormat.actionText(for: .opencode, status: .unconfigured),
                       "OpenCode: вставь cookie в настройках")
        XCTAssertNil(LimitFormat.actionText(for: .codex, status: .ok))
        XCTAssertNil(LimitFormat.actionText(for: .codex, status: .stale))
    }

    func test_fetched_at_label() {
        XCTAssertEqual(LimitFormat.fetchedAt(nil), "нет данных")
        XCTAssertTrue(LimitFormat.fetchedAt(now).hasPrefix("данные на "))
    }
}
