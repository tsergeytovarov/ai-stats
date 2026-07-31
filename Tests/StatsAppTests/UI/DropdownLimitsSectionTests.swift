import XCTest
@testable import StatsApp

final class DropdownLimitsSectionTests: XCTestCase {

    func test_fill_width_is_proportional_to_percent() {
        XCTAssertEqual(DropdownLimitsSection.fillWidth(percent: 0, barWidth: 100), 0)
        XCTAssertEqual(DropdownLimitsSection.fillWidth(percent: 50, barWidth: 100), 50)
        XCTAssertEqual(DropdownLimitsSection.fillWidth(percent: 97, barWidth: 100), 97)
        XCTAssertEqual(DropdownLimitsSection.fillWidth(percent: 100, barWidth: 100), 100)
    }

    // Сервер теоретически может прислать перерасход квоты. Заливка не имеет
    // права вылезти за дорожку — она нарисуется поверх соседней колонки.
    func test_fill_width_never_exceeds_the_track() {
        XCTAssertEqual(DropdownLimitsSection.fillWidth(percent: 140, barWidth: 100), 100)
        XCTAssertEqual(DropdownLimitsSection.fillWidth(percent: -5, barWidth: 100), 0)
    }

    // Полоска обязана быть фиксированной ширины: когда она была резиновой,
    // хвост со временем сброса разной длины растягивал её по-разному и
    // полоски разных строк не выстраивались в колонку.
    func test_bar_width_is_a_fixed_constant() {
        XCTAssertGreaterThan(DropdownLimitsSection.barWidth, 0)
        XCTAssertEqual(DropdownLimitsSection.fillWidth(percent: 100),
                       DropdownLimitsSection.barWidth)
    }
}
