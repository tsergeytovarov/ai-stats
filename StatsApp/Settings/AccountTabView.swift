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

        TextField("Имя", text: $newName)
            .textFieldStyle(.roundedBorder)

        HStack {
            Button("Выбрать аватарку") { pickAvatar() }
            if let pickedAvatar {
                Text("\(pickedAvatar.count) байт").font(.caption).foregroundStyle(.secondary)
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
            Image(systemName: "person.crop.circle")
                .resizable().frame(width: 48, height: 48)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(.headline)
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
    private func formatFriendCode(_ raw: String) -> String {
        guard raw.count == 10 else { return raw }
        let i1 = raw.index(raw.startIndex, offsetBy: 4)
        let i2 = raw.index(raw.startIndex, offsetBy: 8)
        return "\(raw[..<i1])-\(raw[i1..<i2])-\(raw[i2...])"
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= 200 * 1024 else {
                    viewModel.errorMessage = "Аватарка слишком большая (\(data.count) байт). Максимум 200 KB."
                    return
                }
                pickedAvatar = data
                pickedAvatarMime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            } catch {
                viewModel.errorMessage = "Не удалось прочитать файл: \(error.localizedDescription)"
            }
        }
    }
}
