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

    // Спека §9: подпись «данные на HH:MM» должна становиться приглушённой/
    // отличимой, когда статус не ok — иначе stale в интерфейсе неотличим от
    // свежих данных (находка 5 финального ревью).
    func test_fetched_at_label_marks_non_ok_status_visibly() {
        let okLabel = LimitFormat.fetchedAt(now, status: .ok)
        let staleLabel = LimitFormat.fetchedAt(now, status: .stale)
        let throttledLabel = LimitFormat.fetchedAt(now, status: .throttled)
        XCTAssertTrue(okLabel.hasPrefix("данные на "))
        XCTAssertNotEqual(okLabel, staleLabel)
        XCTAssertNotEqual(okLabel, throttledLabel)
    }

    // 429: показываем прошлые цифры и время следующей попытки (спека §9,
    // находка 6 финального ревью — latest() раньше не отдавал retryAfter вообще).
    func test_retry_after_text() {
        XCTAssertEqual(LimitFormat.retryAfterText(now.addingTimeInterval(90 * 60), now: now),
                       "следующая попытка через 1ч 30м")
        XCTAssertEqual(LimitFormat.retryAfterText(now.addingTimeInterval(40 * 60), now: now),
                       "следующая попытка через 40м")
        XCTAssertNil(LimitFormat.retryAfterText(nil, now: now))
        // Время уже прошло — нет смысла врать про «следующую попытку».
        XCTAssertNil(LimitFormat.retryAfterText(now.addingTimeInterval(-60), now: now))
    }
}
