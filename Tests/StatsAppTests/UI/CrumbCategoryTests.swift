import XCTest
import SwiftUI
@testable import StatsApp

final class CrumbCategoryTests: XCTestCase {
    func test_aiCategory_usesPinkCrumb() {
        XCTAssertEqual(CrumbCategory.ai.color, TextColor.crumbAI)
    }
    func test_githubCategory_usesCyanCrumb() {
        XCTAssertEqual(CrumbCategory.github.color, TextColor.crumbGitHub)
    }
    func test_friendsCategory_usesNeutralCrumb() {
        XCTAssertEqual(CrumbCategory.friends.color, TextColor.crumbFriends)
    }
}
