import XCTest
import SwiftUI
@testable import StatsApp

final class LimitRingPaletteTests: XCTestCase {

    // Цвет провайдера постоянный и ни от чего не зависит: три кольца идут
    // подряд без подписей, и цвет — единственное, чем они отличаются.
    func test_provider_colors_are_fixed() {
        XCTAssertEqual(LimitRingPalette.color(for: .codex), LimitRingPalette.codexBlue)
        XCTAssertEqual(LimitRingPalette.color(for: .claude), LimitRingPalette.claudeOrange)
        XCTAssertEqual(LimitRingPalette.color(for: .opencode), LimitRingPalette.openCodeWhite)
    }

    func test_provider_colors_are_distinct() {
        let colors = LimitProvider.allCases.map { LimitRingPalette.color(for: $0) }
        XCTAssertEqual(Set(colors.map(\.description)).count, LimitProvider.allCases.count)
    }

    // Трек нейтральный у всех колец: белое кольцо с белым треком исчезает
    // в светлой теме меню-бара.
    func test_track_is_neutral_not_provider_tinted() {
        XCTAssertEqual(LimitRingPalette.trackColor, Color.primary.opacity(0.15))
    }

    // Заполнение кольца по-прежнему берётся из окна с ближайшим сбросом, а не
    // из худшего: цвет больше не несёт тревогу, но заливка должна отвечать на
    // вопрос «сколько осталось в ближайшее время».
    func test_ring_fill_still_comes_from_soonest_window() {
        let limits = ProviderLimits(
            provider: .claude,
            windows: [
                LimitWindow(windowMinutes: 300, usedPercent: 0,
                            resetsAt: Date(timeIntervalSince1970: 1_000)),
                LimitWindow(windowMinutes: 10080, usedPercent: 95,
                            resetsAt: Date(timeIntervalSince1970: 9_000)),
            ],
            status: .ok, fetchedAt: Date(timeIntervalSince1970: 0), error: nil)

        XCTAssertEqual(limits.ringWindow?.windowMinutes, 300)
        XCTAssertEqual(limits.ringWindow?.usedPercent, 0)
    }
}
