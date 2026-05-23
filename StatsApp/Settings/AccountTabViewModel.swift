import Foundation
import GRDB

@MainActor
final class AccountTabViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case notCreated
        case created(MyProfileRow)
    }

    @Published var state: State = .loading
    @Published var errorMessage: String?
    @Published var isWorking: Bool = false

    private let api: AiuseAPIClient
    private let keychain: KeychainStore
    private let secretBox: SecretBox
    private let db: any DatabaseWriter

    init(api: AiuseAPIClient, keychain: KeychainStore, secretBox: SecretBox, db: any DatabaseWriter) {
        self.api = api
        self.keychain = keychain
        self.secretBox = secretBox
        self.db = db
    }

    func reload() async {
        state = .loading
        do {
            if let profile = try await db.read({ try StatsQueries.loadMyProfile($0) }) {
                state = .created(profile)
            } else {
                state = .notCreated
            }
        } catch {
            errorMessage = "\(error)"
            state = .notCreated
        }
    }

    func createAccount(displayName: String, avatar: Data?, avatarMime: String?) async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        do {
            let resp = try await api.createProfile(
                displayName: displayName, avatar: avatar, avatarMime: avatarMime
            )
            try keychain.set(resp.apiSecret, account: AiuseKeychain.account, service: AiuseKeychain.service)
            secretBox.value = resp.apiSecret  // обновляем memory cache

            let row = MyProfileRow(
                id: 1,
                friendCode: resp.friendCode,
                displayName: displayName,
                avatarPath: nil,
                sharingEnabled: true,
                serverUserId: resp.serverUserId
            )
            try await db.write { try StatsQueries.saveMyProfile($0, row) }
            state = .created(row)
        } catch {
            errorMessage = "Не удалось создать профиль: \(error.localizedDescription)"
        }
    }

    func toggleSharing(_ enabled: Bool) async {
        guard case let .created(profile) = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.patchProfile(sharingEnabled: enabled)
            var updated = profile
            updated.sharingEnabled = enabled
            try await db.write { try StatsQueries.saveMyProfile($0, updated) }
            state = .created(updated)
        } catch {
            errorMessage = "Не удалось переключить шаринг: \(error.localizedDescription)"
        }
    }

    func updateName(_ newName: String) async {
        guard case let .created(profile) = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.patchProfile(displayName: newName)
            var updated = profile
            updated.displayName = newName
            try await db.write { try StatsQueries.saveMyProfile($0, updated) }
            state = .created(updated)
        } catch {
            errorMessage = "Не удалось обновить имя: \(error.localizedDescription)"
        }
    }

    func regenerateFriendCode() async {
        guard case let .created(profile) = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let resp = try await api.regenerateFriendCode()
            var updated = profile
            updated.friendCode = resp.friendCode
            try await db.write { try StatsQueries.saveMyProfile($0, updated) }
            state = .created(updated)
        } catch {
            errorMessage = "Не удалось сгенерировать новый код: \(error.localizedDescription)"
        }
    }

    func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.deleteAccount()
            try keychain.delete(account: AiuseKeychain.account, service: AiuseKeychain.service)
            secretBox.value = nil  // чистим memory cache
            try await db.write { try StatsQueries.deleteMyProfile($0) }
            state = .notCreated
        } catch {
            errorMessage = "Не удалось удалить аккаунт: \(error.localizedDescription)"
        }
    }
}
