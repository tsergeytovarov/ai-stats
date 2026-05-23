import SwiftUI

struct BlockedTabView: View {
    @ObservedObject var viewModel: BlockedTabViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Заблокированные").font(.title2).bold()
                Text("Эти юзеры не могут добавить тебя по friend_code. Разблокировка позволит им снова отправить запрос — связь сама не восстановится.")
                    .foregroundStyle(.secondary).font(.callout)

                if viewModel.isLoading && viewModel.blocked.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if viewModel.blocked.isEmpty {
                    Text("Никого не заблокировал.").foregroundStyle(.secondary).font(.callout)
                } else {
                    VStack(spacing: 0) {
                        ForEach(viewModel.blocked) { entry in
                            row(entry)
                            if entry.friendCode != viewModel.blocked.last?.friendCode {
                                Divider()
                            }
                        }
                    }
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
    private func row(_ entry: BlockDTO) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .resizable().frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.body)
                Text(entry.friendCode).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Разблокировать") {
                Task { await viewModel.unblock(entry) }
            }
        }
        .padding(.vertical, 6)
    }
}
