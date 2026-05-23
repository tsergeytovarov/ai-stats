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
        VStack(alignment: .leading, spacing: 0) {
            Crumb(category: .ai, title: "AI", period: viewModel.period.localizedTitle)

            HeroNumber(MoneyFormatter.popover(viewModel.aiTotals.totalCost), variant: .pink)
                .padding(.top, 4)

            CostDelta(
                current: viewModel.aiTotals.totalCost,
                previous: viewModel.aiTotalsPrev.totalCost,
                period: viewModel.period
            )
            .foregroundStyle(BrandColor.cyanLight)
            .padding(.top, 4)

            Text(DropdownFormat.tokens(viewModel.aiTotals.totalInputTokens + viewModel.aiTotals.totalOutputTokens) + " tokens")
                .font(BrandFont.caption)
                .foregroundStyle(BrandColor.cyanLight.opacity(0.75))
                .padding(.top, 2)

            Text("section.top_models")
                .font(BrandFont.lbl)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(BrandColor.cyanLight.opacity(0.7))
                .padding(.top, 14)
                .padding(.bottom, 6)

            if viewModel.topModels.isEmpty {
                Text("label.no_data").font(BrandFont.caption).foregroundStyle(TextColor.muted)
            } else {
                ForEach(viewModel.topModels.prefix(5), id: \.self) { m in
                    HStack {
                        Text(m.model).font(BrandFont.body)
                        Spacer()
                        Text(MoneyFormatter.popover(m.costUsd))
                            .font(BrandFont.body)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.vertical, 3)
                }
            }

            Spacer(minLength: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("section.trend")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)
                Sparkline(values: viewModel.sparklineSeries, variant: .ai)
                    .frame(height: 38)
            }
        }
    }
}

// MARK: - GitHub section

struct DropdownGitHubSection: View {
    @ObservedObject var viewModel: DropdownViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Crumb(category: .github, title: "GitHub", period: viewModel.period.localizedTitle)

            HeroNumberWithUnit(
                number: "\(viewModel.githubTotals.totalCommits)",
                unit: NSLocalizedString("unit.commits", comment: "")
            )
            .padding(.top, 4)

            Text("+\(viewModel.loc.additions) / −\(viewModel.loc.deletions) " + NSLocalizedString("unit.lines", comment: ""))
                .font(BrandFont.delta)
                .foregroundStyle(BrandColor.cyanLight)
                .padding(.top, 4)

            Text(String(format: NSLocalizedString("unit.repos_active %d", comment: ""), viewModel.topRepos.count))
                .font(BrandFont.caption)
                .foregroundStyle(TextColor.muted)
                .padding(.top, 2)

            Text("section.top_repos")
                .font(BrandFont.lbl)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(BrandColor.cyanLight.opacity(0.7))
                .padding(.top, 14)
                .padding(.bottom, 6)

            ForEach(viewModel.topRepos.prefix(5), id: \.self) { r in
                HStack {
                    Text(DropdownFormat.repoShortName(r.repo))
                        .font(BrandFont.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(r.commits) c · +\(r.additions)")
                        .font(BrandFont.body)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.vertical, 3)
            }

            Spacer(minLength: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("section.trend_additions")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Sparkline(values: viewModel.additionsSeries, variant: .github)
                    .frame(height: 38)
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
