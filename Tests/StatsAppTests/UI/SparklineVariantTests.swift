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

    func test_githubVariant_usesCyanColors() {
        let v = SparklineVariant.github
        let first = NSColor(v.strokeColors[0]).usingColorSpace(.sRGB)!
        XCTAssertEqual(first.greenComponent, 230/255.0, accuracy: 0.005)  // #4FE6FF
    }
}
