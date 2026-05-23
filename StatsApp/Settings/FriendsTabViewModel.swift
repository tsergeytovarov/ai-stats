import Foundation
import GRDB

@MainActor
final class FriendsTabViewModel: ObservableObject {
    @Published var friends: [FriendProfileRow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newFriendCode: String = ""
    @Published var addInProgress = false

    private let api: AiuseAPIClient
    private let db: any DatabaseWriter
    private let hasAccount: () -> Bool

    init(api: AiuseAPIClient, db: any DatabaseWriter, hasAccount: @escaping () -> Bool) {
        self.api = api
        self.db = db
        self.hasAccount = hasAccount
    }

    func reload() async {
        guard hasAccount() else {
            friends = []
            errorMessage = "Сначала создай аккаунт на вкладке «Аккаунт»."
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            // 1. Сначала локальный кэш — мгновенный рендер
            friends = try await db.read { try StatsQueries.loadFriendProfiles($0) }

            // 2. Запрос на сервер — обновляет кэш + догружает аватарки
            let serverList = try await api.listFriends()
            let now = Date().timeIntervalSince1970
            try await db.write { db in
                for f in serverList {
                    let existing = try FriendProfileRow.fetchOne(db, key: f.friendCode)
                    let row = FriendProfileRow(
                        friendCode: f.friendCode,
                        displayName: f.displayName,
                        sharingEnabled: f.sharingEnabled,
                        avatarBlob: existing?.avatarBlob,
                        avatarMime: existing?.avatarMime,
                        avatarEtag: existing?.avatarEtag,
                        lastFetchedAt: now
                    )
                    try row.save(db)
                }
                let codes = serverList.map { $0.friendCode }
                try StatsQueries.deleteFriendProfilesNotIn(db, friendCodes: codes)
            }

            friends = try await db.read { try StatsQueries.loadFriendProfiles($0) }
        } catch {
            errorMessage = "Не удалось загрузить друзей: \(error.localizedDescription)"
        }
    }

    func addFriend() async {
        let code = newFriendCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        addInProgress = true
        defer { addInProgress = false }
        errorMessage = nil
        do {
            let added = try await api.addFriend(friendCode: code)
            try await db.write { db in
                let row = FriendProfileRow(
                    friendCode: added.friendCode,
                    displayName: added.displayName,
                    sharingEnabled: added.sharingEnabled,
                    avatarBlob: nil,
                    avatarMime: nil,
                    avatarEtag: nil,
                    lastFetchedAt: Date().timeIntervalSince1970
                )
                try row.save(db)
            }
            friends = try await db.read { try StatsQueries.loadFriendProfiles($0) }
            newFriendCode = ""
        } catch {
            errorMessage = "Не удалось добавить: \(error.localizedDescription)"
        }
    }

    func removeFriend(_ friend: FriendProfileRow, block: Bool = false) async {
        errorMessage = nil
        do {
            try await api.removeFriend(friendCode: friend.friendCode, block: block)
            try await db.write { db in
                _ = try FriendProfileRow.deleteOne(db, key: friend.friendCode)
            }
            friends.removeAll { $0.friendCode == friend.friendCode }
        } catch {
            errorMessage = "Не удалось удалить: \(error.localizedDescription)"
        }
    }
}
