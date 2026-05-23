import XCTest
import SwiftUI
@testable import StatsApp

final class TokensTests: XCTestCase {
    func test_brandPink_resolvesToExpectedRGB() {
        let c = NSColor(BrandColor.pink).usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent, 1.0, accuracy: 0.005)
        XCTAssertEqual(c.greenComponent, 45.0/255.0, accuracy: 0.005)
        XCTAssertEqual(c.blueComponent, 109.0/255.0, accuracy: 0.005)
    }

    func test_brandCyan_resolvesToExpectedRGB() {
        let c = NSColor(BrandColor.cyan).usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent, 0.0, accuracy: 0.005)
        XCTAssertEqual(c.greenComponent, 184.0/255.0, accuracy: 0.005)
        XCTAssertEqual(c.blueComponent, 230.0/255.0, accuracy: 0.005)
    }

    func test_pinkLight_isLighterThanPink() {
        let pink = NSColor(BrandColor.pink).usingColorSpace(.sRGB)!
        let light = NSColor(BrandColor.pinkLight).usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(light.greenComponent, pink.greenComponent)
    }
}
