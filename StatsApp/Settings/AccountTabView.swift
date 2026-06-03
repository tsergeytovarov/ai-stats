import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AccountTabView: View {
    @ObservedObject var viewModel: AccountTabViewModel
    @State private var newName: String = ""
    @State private var pickedAvatar: Data? = nil
    @State private var pickedAvatarMime: String? = nil
    @State private var showRegenerateConfirm = false
    @State private var showDeleteConfirm = false
    @State private var editingName: String = ""
    @State private var isEditingName: Bool = false
    @State private var includePrivateRepos = false
    @State private var globalOptInLocal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.state {
                case .loading:
                    HStack { Spacer(); ProgressView(); Spacer() }
                case .notCreated:
                    notCreatedView
                case .created(let profile):
                    createdView(profile: profile)
                }

                if let err = viewModel.errorMessage {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await viewModel.reload() }
    }

    @ViewBuilder
    private var notCreatedView: some View {
        Text("Создать аккаунт").font(.title2).bold()
        Text("Без аккаунта недоступен лидерборд и виджет с лидербордом. Локальная статистика работает как и раньше.")
            .foregroundStyle(.secondary).font(.callout)

        Button {
            Task { await viewModel.signInWithGitHub(includePrivate: includePrivateRepos) }
        } label: {
            Label("Войти через GitHub", systemImage: "person.badge.key")
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isWorking)

        Toggle("Включая приватные репозитории", isOn: $includePrivateRepos)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Text("Или создать аккаунт вручную").font(.callout).foregroundStyle(.secondary)

        TextField("Имя", text: $newName)
            .textFieldStyle(.roundedBorder)

        HStack(spacing: 12) {
            AvatarView(data: pickedAvatar, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Button(pickedAvatar == nil ? "Выбрать аватарку" : "Сменить аватарку") {
                    pickAvatar()
                }
                if let pickedAvatar {
                    Text("\(pickedAvatar.count) байт").font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        Button("Создать аккаунт") {
            Task {
                await viewModel.createAccount(
                    displayName: newName,
                    avatar: pickedAvatar,
                    avatarMime: pickedAvatarMime
                )
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isWorking)
    }

    @ViewBuilder
    private func createdView(profile: MyProfileRow) -> some View {
        HStack(spacing: 12) {
            AvatarView(data: profile.avatarBlob, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                if isEditingName {
                    HStack {
                        TextField("Имя", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await saveName() } }
                        Button("Сохранить") { Task { await saveName() } }
                            .disabled(editingName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isWorking)
                        Button("Отмена") { isEditingName = false }
                    }
                } else {
                    HStack {
                        Text(profile.displayName).font(.headline)
                        Button("Изменить") {
                            editingName = profile.displayName
                            isEditingName = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                Button(profile.avatarBlob == nil ? "Добавить аватарку" : "Сменить аватарку") {
                    changeAvatar()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(viewModel.isWorking)
                Text("server_user_id: \(profile.serverUserId)").font(.caption).foregroundStyle(.secondary)
            }
        }

        Divider()

        Text("Твой код для друзей").font(.headline)
        HStack {
            Text(formatFriendCode(profile.friendCode))
                .font(.system(.title3, design: .monospaced))
            Spacer()
            Button("Копировать") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(profile.friendCode, forType: .string)
            }
        }

        Divider()

        Toggle("Шарить статистику", isOn: Binding(
            get: { profile.sharingEnabled },
            set: { newVal in Task { await viewModel.toggleSharing(newVal) } }
        ))
        Text("Если выключено: ты не отправляешь свои данные и не видишь чужие.")
            .font(.caption).foregroundStyle(.secondary)

        Toggle("Показывать в публичном лидерборде", isOn: Binding(
            get: { globalOptInLocal },
            set: { newValue in
                globalOptInLocal = newValue
                Task { await viewModel.toggleGlobalOptIn(newValue) }
            }
        ))
        .help("Твой handle, аватар и цифры станут видны публично на сайте")

        Divider()

        Text("Опасная зона").font(.headline).foregroundStyle(.red)
        Button("Сгенерировать новый код") {
            showRegenerateConfirm = true
        }
        .confirmationDialog(
            "Новый код заменит текущий. Все друзья будут удалены — им придётся добавить тебя заново. Твоя история использования сохранится.",
            isPresented: $showRegenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Сгенерировать", role: .destructive) {
                Task { await viewModel.regenerateFriendCode() }
            }
            Button("Отмена", role: .cancel) {}
        }

        Button("Удалить аккаунт") {
            showDeleteConfirm = true
        }
        .foregroundStyle(.red)
        .confirmationDialog(
            "Это удалит твой профиль, всю историю на сервере и все связи с друзьями. Локальная статистика останется. Действие необратимо.",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить аккаунт", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    /// "XK7P3M9Q2A" → "XK7P-3M9Q-2A"
    private func saveName() async {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        await viewModel.updateName(name)
        if viewModel.errorMessage == nil {
            isEditingName = false
        }
    }

    private func formatFriendCode(_ raw: String) -> String {
        guard raw.count == 10 else { return raw }
        let i1 = raw.index(raw.startIndex, offsetBy: 4)
        let i2 = raw.index(raw.startIndex, offsetBy: 8)
        return "\(raw[..<i1])-\(raw[i1..<i2])-\(raw[i2...])"
    }

    private func pickAvatar() {
        guard let picked = pickAvatarFile() else { return }
        pickedAvatar = picked.data
        pickedAvatarMime = picked.mime
    }

    /// Для существующего аккаунта: выбрать файл и сразу залить через VM.
    private func changeAvatar() {
        guard let picked = pickAvatarFile() else { return }
        Task { await viewModel.updateAvatar(picked.data, mime: picked.mime) }
    }

    /// Открывает NSOpenPanel, читает JPEG/PNG, валидирует размер.
    /// Ошибки кладёт в viewModel.errorMessage и возвращает nil.
    private func pickAvatarFile() -> (data: Data, mime: String)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 200 * 1024 else {
                viewModel.errorMessage = "Аватарка слишком большая (\(data.count) байт). Максимум 200 KB."
                return nil
            }
            let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            return (data, mime)
        } catch {
            viewModel.errorMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
            return nil
        }
    }
}
