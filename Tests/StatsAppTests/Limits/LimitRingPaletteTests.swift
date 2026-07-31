import XCTest
import SwiftUI
@testable import StatsApp

final class LimitRingPaletteTests: XCTestCase {

    // Фирменный цвет живёт только в спокойном состоянии. Выше порогов все три
    // провайдера одинаковые: это сигнал «тормози», а не «кто это».
    func test_brand_colors_only_below_warning() {
        XCTAssertEqual(LimitRingPalette.color(for: .codex, severity: .calm), LimitRingPalette.codexBlue)
        XCTAssertEqual(LimitRingPalette.color(for: .claude, severity: .calm), LimitRingPalette.claudeOrange)
        XCTAssertEqual(LimitRingPalette.color(for: .opencode, severity: .calm), LimitRingPalette.openCodeWhite)

        for provider in LimitProvider.allCases {
            XCTAssertEqual(LimitRingPalette.color(for: provider, severity: .warning),
                           LimitRingPalette.warningYellow)
            XCTAssertEqual(LimitRingPalette.color(for: provider, severity: .critical),
                           BrandColor.danger)
        }
    }

    // Заливка идёт по ближайшему окну, цвет — по худшему. Проверяем связку
    // целиком, а не по кусочкам.
    func test_fill_and_color_come_from_different_windows() {
        let limits = ProviderLimits(
            provider: .claude,
            windows: [
                LimitWindow(windowMinutes: 300, usedPercent: 0,
                            resetsAt: Date(timeIntervalSince1970: 1_000)),
                LimitWindow(windowMinutes: 10080, usedPercent: 95,
                            resetsAt: Date(timeIntervalSince1970: 9_000)),
            ],
            status: .ok, fetchedAt: Date(timeIntervalSince1970: 0), error: nil)

        XCTAssertEqual(limits.ringWindow?.usedPercent, 0)
        XCTAssertEqual(LimitRingPalette.color(
            for: .claude,
            severity: LimitThresholds.severity(worstPercent: limits.worstPercent!)),
                       BrandColor.danger)
    }

    // Трек нейтральный у всех колец: белое кольцо с белым треком исчезает
    // в светлой теме меню-бара.
    func test_track_is_neutral_not_provider_tinted() {
        XCTAssertEqual(LimitRingPalette.trackColor, Color.primary.opacity(0.15))
    }
}
