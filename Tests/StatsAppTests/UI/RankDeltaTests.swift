import XCTest
@testable import StatsApp

final class RankDeltaTests: XCTestCase {
    func test_climbedUp_isUpWithMagnitude() {
        // Был #11, стал #1 — поднялся на 10 позиций.
        let result = DropdownFormat.formatRankDelta(current: 1, previous: 11)
        XCTAssertEqual(result?.kind, .change(magnitude: 10, direction: .up))
    }

    func test_fellDown_isDownWithMagnitude() {
        // Был #2, стал #5 — опустился на 3 позиции.
        let result = DropdownFormat.formatRankDelta(current: 5, previous: 2)
        XCTAssertEqual(result?.kind, .change(magnitude: 3, direction: .down))
    }

    func test_previousNil_isNew() {
        let result = DropdownFormat.formatRankDelta(current: 7, previous: nil)
        XCTAssertEqual(result?.kind, .new)
    }

    func test_sameRank_returnsNil() {
        let result = DropdownFormat.formatRankDelta(current: 3, previous: 3)
        XCTAssertNil(result)
    }
}
