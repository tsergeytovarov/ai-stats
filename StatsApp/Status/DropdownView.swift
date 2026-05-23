import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DropdownViewModel
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Period picker (общий для всех вкладок)
            Picker("", selection: $viewModel.period) {
                ForEach(Period.allCases) { p in Text(p.titleKey).tag(p) }
            }
            .pickerStyle(.segmented)

            // Section picker — AI / GitHub / Лидерборд
            Picker("", selection: $viewModel.section) {
                ForEach(availableSections) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            // Содержимое выбранной секции
            switch viewModel.section {
            case .ai:
                DropdownAISection(viewModel: viewModel)
            case .github:
                DropdownGitHubSection(viewModel: viewModel)
            case .leaderboard:
                DropdownLeaderboardSection(viewModel: viewModel)
            }

            Divider()

            HStack {
                Text(String(format: NSLocalizedString("footer.last_sync %@", comment: ""),
                            viewModel.lastSyncDescription))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }.buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.loadLeaderboard()
        }
    }

    /// Список секций, доступных в текущей конфигурации.
    /// GitHub — только если githubEnabled. Лидерборд — всегда (показывает hint если нет аккаунта).
    private var availableSections: [DropdownSection] {
        var sections: [DropdownSection] = [.ai]
        if viewModel.githubEnabled {
            sections.append(.github)
        }
        sections.append(.leaderboard)
        return sections
    }
}
