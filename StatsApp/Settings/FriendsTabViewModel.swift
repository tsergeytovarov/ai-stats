import Foundation

@MainActor
final class FriendsTabViewModel: ObservableObject {
    @Published var friends: [FriendDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var newFriendCode: String = ""
    @Published var addInProgress = false

    private let api: AiuseAPIClient
    private let hasAccount: () -> Bool

    init(api: AiuseAPIClient, hasAccount: @escaping () -> Bool) {
        self.api = api
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
            friends = try await api.listFriends()
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
            friends.insert(added, at: 0)
            newFriendCode = ""
        } catch {
            errorMessage = "Не удалось добавить: \(error.localizedDescription)"
        }
    }

    func removeFriend(_ friend: FriendDTO, block: Bool = false) async {
        errorMessage = nil
        do {
            try await api.removeFriend(friendCode: friend.friendCode, block: block)
            friends.removeAll { $0.friendCode == friend.friendCode }
        } catch {
            errorMessage = "Не удалось удалить: \(error.localizedDescription)"
        }
    }
}
