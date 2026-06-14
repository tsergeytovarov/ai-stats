import SwiftUI

struct FriendsTabView: View {
    @ObservedObject var viewModel: FriendsTabViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                addSection
                Divider()
                listSection
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
    private var addSection: some View {
        Text("Добавить друга").font(.headline)
        HStack {
            TextField("Код (например, XK7P-3M9Q-2A)", text: $viewModel.newFriendCode)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { Task { await viewModel.addFriend() } }
            Button("Добавить") {
                Task { await viewModel.addFriend() }
            }
            .disabled(viewModel.newFriendCode.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.addInProgress)
        }
    }

    @ViewBuilder
    private var listSection: some View {
        Text("Мои друзья (\(viewModel.friends.count))").font(.headline)
        if viewModel.isLoading && viewModel.friends.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
        } else if viewModel.friends.isEmpty {
            Text("Пока никого. Поделись своим кодом из вкладки «Аккаунт» — друзья смогут добавить тебя по нему.")
                .foregroundStyle(.secondary).font(.callout)
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.friends, id: \.friendCode) { friend in
                    friendRow(friend)
                    if friend.friendCode != viewModel.friends.last?.friendCode {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func friendRow(_ friend: FriendProfileRow) -> some View {
        HStack(spacing: 10) {
            AvatarView(data: friend.avatarBlob, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName).font(.body)
                Text(FriendCode.formatted(friend.friendCode))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !friend.sharingEnabled {
                    Text("шаринг выключен").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            Menu {
                Button("Удалить") {
                    Task { await viewModel.removeFriend(friend, block: false) }
                }
                Button("Удалить и заблокировать", role: .destructive) {
                    Task { await viewModel.removeFriend(friend, block: true) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 6)
    }
}
