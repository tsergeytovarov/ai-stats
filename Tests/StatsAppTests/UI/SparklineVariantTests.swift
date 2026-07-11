import XCTest
import SwiftUI
@testable import StatsApp

final class SparklineVariantTests: XCTestCase {
    func test_aiVariant_usesPinkColors() {
        let v = SparklineVariant.ai
        XCTAssertEqual(v.strokeColors.count, 2)
        let first = NSColor(v.strokeColors[0]).usingColorSpace(.sRGB)!
        XCTAssertEqual(first.greenComponent, 95/255.0, accuracy: 0.005)  // #FF5FA0
    }
}
