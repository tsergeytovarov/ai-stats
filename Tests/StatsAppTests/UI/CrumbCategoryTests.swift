import XCTest
import SwiftUI
@testable import StatsApp

final class CrumbCategoryTests: XCTestCase {
    func test_aiCategory_usesPinkCrumb() {
        XCTAssertEqual(CrumbCategory.ai.color, TextColor.crumbAI)
    }
}
