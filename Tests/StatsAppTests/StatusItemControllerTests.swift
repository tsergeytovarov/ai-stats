import XCTest
@testable import StatsApp

final class StatusItemControllerTests: XCTestCase {
    // MARK: - capsuleWidth

    func test_capsuleWidth_returnsPositive_forEmptyText() {
        let w = StatusItemController.capsuleWidth(for: "")
        // Минимум — ember(12) + spacing(4) + padding(16) = 32pt без текста.
        XCTAssertGreaterThanOrEqual(w, 32)
    }

    func test_capsuleWidth_growsWithLongerText() {
        let short = StatusItemController.capsuleWidth(for: "$0.00")
        let long = StatusItemController.capsuleWidth(for: "$1234.56")
        XCTAssertGreaterThan(long, short, "ширина должна расти на более длинном тексте")
    }

    func test_capsuleWidth_isStable_forSameInput() {
        // Детерминированность: один и тот же priceText → один и тот же width.
        // Это главное свойство — раньше fittingSize возвращал разные значения
        // на каждом тике, capsule прыгал в 3 стадии.
        let a = StatusItemController.capsuleWidth(for: "$879.85")
        let b = StatusItemController.capsuleWidth(for: "$879.85")
        XCTAssertEqual(a, b)
    }

    func test_capsuleWidth_realisticValuesAreReasonable() {
        // Sanity-check: типичное "$1.23" не должно быть < 50pt и не должно быть > 200pt.
        let w = StatusItemController.capsuleWidth(for: "$1.23")
        XCTAssertGreaterThan(w, 50)
        XCTAssertLessThan(w, 200)
    }

    func test_capsuleWidth_addsExactRingsGeometry_whenShowsRingsTrue() {
        // Дельта между "с кольцами" и "без колец" обязана точно совпасть с
        // геометрией блока колец в MenuBarCapsuleView:
        //   доп. spacing(4) внешнего HStack — с кольцами у него 3 ребёнка
        //   (Ember, Text, HStack колец) вместо 2, то есть 2 промежутка вместо 1;
        //   + padding(.leading, 2) перед блоком колец;
        //   + 3 кольца по 10pt + 2 промежутка по 3pt между ними (HStack(spacing: 3)).
        // Раньше второй spacing(4) не добавлялся — правый край последнего кольца
        // уезжал под обрезку NSStatusItem. Тест ловит именно эту регрессию, а не
        // фиксирует текущее магическое число.
        let withoutRings = StatusItemController.capsuleWidth(for: "$1.23", showsRings: false)
        let withRings = StatusItemController.capsuleWidth(for: "$1.23", showsRings: true)
        let expectedDelta: CGFloat = 4 + 2 + 3 * 10 + 2 * 3
        XCTAssertEqual(withRings - withoutRings, expectedDelta)
    }
}
