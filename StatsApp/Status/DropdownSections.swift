import SwiftUI

// MARK: - delta views

private extension DeltaDirection {
    var color: Color {
        switch self {
        case .up:   return .green
        case .down: return .red
        }
    }
}

struct CostDelta: View {
    let current: Double
    let previous: Double
    let period: Period

    var body: some View {
        if let content = DropdownFormat.formatCostDelta(current: current, previous: previous, period: period) {
            HStack(spacing: 4) {
                Text(content.arrow + " " + content.amount)
                    .foregroundStyle(content.direction.color)
                Text(NSLocalizedString(content.labelKey, comment: ""))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}

struct RankDelta: View {
    let current: Int
    let previous: Int?

    var body: some View {
        Group {
            if let content = DropdownFormat.formatRankDelta(current: current, previous: previous) {
                switch content.kind {
                case .new:
                    Text(NSLocalizedString("delta.new", comment: ""))
                        .foregroundStyle(.secondary)
                case .change(let magnitude, let direction):
                    let arrow = direction == .up ? "▲" : "▼"
                    Text("\(arrow)\(magnitude)")
                        .foregroundStyle(direction.color)
                }
            } else {
                Text(" ")   // зарезервировать место, чтобы аватарки не прыгали
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(width: 32, alignment: .leading)
    }
}

// MARK: - AI section

struct DropdownAISection: View {
    @ObservedObject var viewModel: DropdownViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "$%.2f", viewModel.aiTotals.totalCost))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                CostDelta(
                    current: viewModel.aiTotals.totalCost,
                    previous: viewModel.aiTotalsPrev.totalCost,
                    period: viewModel.period
                )
                Text(DropdownFormat.tokens(viewModel.aiTotals.totalInputTokens + viewModel.aiTotals.totalOutputTokens) + " tokens")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("section.ai_usage").font(.headline)
                if viewModel.bySource.isEmpty {
                    Text("label.no_data").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.bySource, id: \.source) { src in
                        HStack {
                            Text(src.source)
                            Spacer()
                            Text(String(format: "$%.2f", src.costUsd))
                            Text(DropdownFormat.tokens(src.inputTokens + src.outputTokens) + " tok")
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("section.top_models").font(.headline)
                if viewModel.topModels.isEmpty {
                    Text("label.no_data").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.topModels, id: \.self) { m in
                        HStack {
                            Text(m.model)
                            Spacer()
                            Text(String(format: "$%.2f", m.costUsd))
                            Text(DropdownFormat.tokens(m.inputTokens + m.outputTokens) + " tok")
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("section.trend").font(.caption).foregroundStyle(.secondary)
                Sparkline(values: viewModel.sparklineSeries)
            }
        }
    }
}

// MARK: - GitHub section

struct DropdownGitHubSection: View {
    @ObservedObject var viewModel: DropdownViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.githubTotals.totalCommits)")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("commits • \(viewModel.githubTotals.uniqueRepos) repos")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("section.github").font(.headline)
                Text(String(format: NSLocalizedString("github.loc %@ %@", comment: ""),
                            DropdownFormat.loc(viewModel.loc.additions),
                            DropdownFormat.loc(viewModel.loc.deletions)))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if viewModel.githubTotals.totalCommits > 0 && !viewModel.topRepos.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("section.top_repos").font(.headline)
                    ForEach(viewModel.topRepos, id: \.self) { r in
                        HStack {
                            Text(DropdownFormat.repoShortName(r.repo))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(r.commits) c")
                            Text(DropdownFormat.loc(r.additions) + " +")
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }

            if viewModel.additionsSeries.contains(where: { $0 > 0 }) {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("section.trend_additions").font(.caption).foregroundStyle(.secondary)
                    Sparkline(values: viewModel.additionsSeries, tint: .githubGreen)
                }
            }
        }
    }
}

// MARK: - Leaderboard section

struct DropdownLeaderboardSection: View {
    @ObservedObject var viewModel: DropdownViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.leaderboardLoading && viewModel.leaderboard.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 20)
            } else if let err = viewModel.leaderboardError, viewModel.leaderboard.isEmpty {
                Text(err).font(.callout).foregroundStyle(.red)
            } else if viewModel.leaderboard.isEmpty {
                Text("Создай аккаунт в Настройки → Аккаунт и шарь статистику чтобы увидеть лидерборд.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.leaderboard) { entry in
                        HStack(spacing: 10) {
                            Text("\(entry.rank).")
                                .frame(width: 22, alignment: .trailing)
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                            RankDelta(current: entry.rank, previous: entry.previousRank)
                            AvatarView(data: viewModel.friendAvatars[entry.friendCode], size: 28)
                            Text(entry.isMe ? "Я" : entry.displayName)
                                .fontWeight(entry.isMe ? .semibold : .regular)
                            Spacer()
                            Text(DropdownFormat.tokens(entry.tokensTotal) + " tok")
                                .foregroundStyle(.secondary)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                if viewModel.leaderboard.count == 1 {
                    Text("Добавь друзей в Настройки → Друзья, чтобы увидеть других.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let err = viewModel.leaderboardError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
