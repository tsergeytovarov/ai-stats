import Foundation

@MainActor
final class BlockedTabViewModel: ObservableObject {
    @Published var blocked: [BlockDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: AiuseAPIClient
    private let hasAccount: () -> Bool

    init(api: AiuseAPIClient, hasAccount: @escaping () -> Bool) {
        self.api = api
        self.hasAccount = hasAccount
    }

    func reload() async {
        guard hasAccount() else {
            blocked = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            blocked = try await api.listBlocks()
        } catch {
            errorMessage = "Не удалось загрузить блок-лист: \(error.localizedDescription)"
        }
    }

    func unblock(_ entry: BlockDTO) async {
        errorMessage = nil
        do {
            try await api.unblock(friendCode: entry.friendCode)
            blocked.removeAll { $0.friendCode == entry.friendCode }
        } catch {
            errorMessage = "Не удалось разблокировать: \(error.localizedDescription)"
        }
    }
}
