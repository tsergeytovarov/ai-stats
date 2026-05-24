import XCTest
import GRDB
@testable import StatsApp

@MainActor
final class DropdownViewModelAvatarsTests: XCTestCase {
    var dbq: DatabaseQueue!
    var vm: DropdownViewModel!

    override func setUpWithError() throws {
        dbq = try DatabaseQueue()
        try Database.migrate(dbq)
    }

    private func makeVM() async -> DropdownViewModel {
        let coord = await SyncCoordinator(db: dbq, now: Date.init)
        return DropdownViewModel(db: dbq, syncCoordinator: coord, hasAccount: { true })
    }

    private func seed(myBlob: Data?, friendBlobs: [(code: String, blob: Data?)]) async throws {
        try await dbq.write { db in
            let me = MyProfileRow(
                id: 1,
                friendCode: "ME00000001",
                displayName: "Я",
                avatarPath: nil,
                sharingEnabled: true,
                serverUserId: 1,
                avatarBlob: myBlob,
                avatarMime: myBlob != nil ? "image/jpeg" : nil,
                avatarEtag: nil
            )
            try StatsQueries.saveMyProfile(db, me)
            for f in friendBlobs {
                let row = FriendProfileRow(
                    friendCode: f.code,
                    displayName: f.code,
                    sharingEnabled: true,
                    avatarBlob: f.blob,
                    avatarMime: f.blob != nil ? "image/jpeg" : nil,
                    avatarEtag: nil,
                    lastFetchedAt: 0
                )
                try row.save(db)
            }
        }
    }

    private func entry(_ code: String, isMe: Bool, rank: Int) -> LeaderboardEntry {
        LeaderboardEntry(
            friendCode: code,
            displayName: code,
            rank: rank,
            previousRank: nil,
            tokensTotal: 0,
            isMe: isMe
        )
    }

    func test_reloadAvatars_picksUpFriendBlobs() async throws {
        let blob = Data([0xFF, 0xD8, 0xFF])
        try await seed(myBlob: nil, friendBlobs: [("FR00000001", blob), ("FR00000002", nil)])
        vm = await makeVM()
        vm.leaderboard = [
            entry("FR00000001", isMe: false, rank: 1),
            entry("FR00000002", isMe: false, rank: 2),
        ]

        await vm.reloadAvatars()

        XCTAssertEqual(vm.friendAvatars["FR00000001"], blob)
        XCTAssertNil(vm.friendAvatars["FR00000002"])
    }

    func test_reloadAvatars_includesMyAvatarFromMyProfile() async throws {
        let myBlob = Data([0x89, 0x50, 0x4E, 0x47])
        try await seed(myBlob: myBlob, friendBlobs: [])
        vm = await makeVM()
        vm.leaderboard = [
            entry("ME00000001", isMe: true, rank: 1),
        ]

        await vm.reloadAvatars()

        XCTAssertEqual(vm.friendAvatars["ME00000001"], myBlob)
    }

    func test_reloadAvatars_myCodeNotInLeaderboard_skipsMe() async throws {
        // Если меня нет в текущем периоде — не лезем в friendAvatars зря.
        try await seed(myBlob: Data([0x00]), friendBlobs: [])
        vm = await makeVM()
        vm.leaderboard = [
            entry("FR00000001", isMe: false, rank: 1),
        ]

        await vm.reloadAvatars()

        XCTAssertNil(vm.friendAvatars["ME00000001"])
    }

    func test_reloadAvatars_emptyLeaderboard_resetsMap() async throws {
        try await seed(myBlob: Data([0x00]), friendBlobs: [("FR00000001", Data([0xFF]))])
        vm = await makeVM()
        vm.leaderboard = []
        vm.friendAvatars = ["stale": Data([0xAA])]

        await vm.reloadAvatars()

        XCTAssertTrue(vm.friendAvatars.isEmpty)
    }
}
