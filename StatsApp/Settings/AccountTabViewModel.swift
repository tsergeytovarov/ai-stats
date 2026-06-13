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

    /// Колбэк после успешного GitHub-входа (AppContainer вешает live-пересборку источников). nil в тестах → no-op.
    var onSignedIn: (() async -> Void)?

    private let api: AiuseAPIClient
    private let auth: GitHubSignInService
    private let secretsStore: SecretsStore
    private let secretBox: SecretBox
    private let githubTokenBox: GithubTokenBox
    private let githubLoginBox: GithubLoginBox
    private let db: any DatabaseWriter

    init(api: AiuseAPIClient,
         auth: GitHubSignInService,
         secretsStore: SecretsStore,
         secretBox: SecretBox,
         githubTokenBox: GithubTokenBox,
         githubLoginBox: GithubLoginBox,
         db: any DatabaseWriter) {
        self.api = api
        self.auth = auth
        self.secretsStore = secretsStore
        self.secretBox = secretBox
        self.githubTokenBox = githubTokenBox
        self.githubLoginBox = githubLoginBox
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
            try secretsStore.setAiuse(resp.apiSecret)
            secretBox.value = resp.apiSecret  // обновляем memory cache

            let row = MyProfileRow(
                id: 1,
                friendCode: resp.friendCode,
                displayName: displayName,
                avatarPath: nil,
                sharingEnabled: true,
                serverUserId: resp.serverUserId,
                avatarBlob: avatar,
                avatarMime: avatarMime,
                // ETag получим при первом GET /avatars/{мой_код} — пока nil,
                // локального blob достаточно для рендера.
                avatarEtag: nil
            )
            try await db.write { try StatsQueries.saveMyProfile($0, row) }
            state = .created(row)
        } catch {
            errorMessage = "Не удалось создать профиль: \(error.localizedDescription)"
        }
    }

    /// Вход через GitHub OAuth: брокер-флоу → exchange → сохранить секреты и профиль.
    /// Создаёт фрешевый профиль; старый api_secret-аккаунт не мигрируется (device_token перезаписывается).
    func signInWithGitHub(includePrivate: Bool) async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            let linkExisting: Bool
            let priorSharing: Bool
            if case let .created(existing) = state {
                linkExisting = true
                priorSharing = existing.sharingEnabled
            } else {
                linkExisting = false
                priorSharing = false
            }
            let resp = try await auth.signIn(provider: "github", includePrivate: includePrivate, linkExisting: linkExisting)

            try secretsStore.setAiuse(resp.deviceToken)
            secretBox.value = resp.deviceToken

            // Полная синхронизация: берём реальное состояние шаринга с сервера, а не
            // угадываем. Фолбэк на эвристику (новый профиль приватен, линк сохраняет
            // прежний выбор), только если GET не прошёл — например офлайн.
            let serverSharing = (try? await api.getMyProfile())?.sharingEnabled
            let resolvedSharing = serverSharing ?? (linkExisting ? priorSharing : false)

            if let token = resp.githubToken {
                try secretsStore.setGithubAuth(token: token, login: resp.githubLogin)
                githubTokenBox.value = token
                githubLoginBox.value = resp.githubLogin ?? ""
            }

            let row = MyProfileRow(
                id: 1,
                friendCode: resp.friendCode,
                displayName: resp.githubLogin ?? "anon",
                avatarPath: nil,
                sharingEnabled: resolvedSharing,
                serverUserId: resp.serverUserId,
                avatarBlob: nil,
                avatarMime: nil,
                avatarEtag: nil
            )
            try await db.write { try StatsQueries.saveMyProfile($0, row) }
            state = .created(row)

            // аватарка с GitHub (best-effort, не критично если не вышло)
            if let login = resp.githubLogin,
               let (avatarData, mime) = await GithubAvatar.fetch(login: login) {
                do {
                    _ = try await api.patchProfile(avatar: avatarData, avatarMime: mime)
                    try await db.write { try StatsQueries.updateMyAvatar($0, blob: avatarData, mime: mime, etag: nil) }
                    if case let .created(p) = state {
                        var updated = p
                        updated.avatarBlob = avatarData
                        updated.avatarMime = mime
                        updated.avatarEtag = nil
                        state = .created(updated)
                    }
                } catch {
                    // аватар не критичен — лог в errorMessage не пишем, чтобы не пугать
                }
            }
            await onSignedIn?()
        } catch AuthError.cancelled {
            // молча — юзер сам закрыл окно входа
        } catch {
            errorMessage = "Не удалось войти: \(error.localizedDescription)"
        }
    }

    /// Тогл публичного глобального лидерборда (push-only в фазе 1).
    func toggleGlobalOptIn(_ enabled: Bool) async {
        guard case .created = state else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await api.patchProfile(globalOptIn: enabled)
        } catch {
            errorMessage = "Не удалось переключить публичный лидерборд: \(error.localizedDescription)"
        }
    }

    /// Меняет аватар существующего аккаунта: PATCH /profiles/me + локальный blob.
    /// ETag сбрасывается — догрузится в следующий sync через GET /avatars.
    func updateAvatar(_ avatar: Data, mime: String) async {
        guard case let .created(profile) = state else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        do {
            _ = try await api.patchProfile(avatar: avatar, avatarMime: mime)
            try await db.write {
                try StatsQueries.updateMyAvatar($0, blob: avatar, mime: mime, etag: nil)
            }
            var updated = profile
            updated.avatarBlob = avatar
            updated.avatarMime = mime
            updated.avatarEtag = nil
            state = .created(updated)
        } catch {
            errorMessage = "Не удалось обновить аватарку: \(error.localizedDescription)"
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
            try secretsStore.setAiuse(String?.none)  // оставляет combined-item с github внутри
            secretBox.value = nil  // чистим memory cache
            try await db.write { try StatsQueries.deleteMyProfile($0) }
            state = .notCreated
        } catch {
            errorMessage = "Не удалось удалить аккаунт: \(error.localizedDescription)"
        }
    }
}
