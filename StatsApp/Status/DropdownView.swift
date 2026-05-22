import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DropdownViewModel
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        content
            .padding(16)
            .frame(width: 380)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $viewModel.period) {
                ForEach(Period.allCases) { p in Text(p.titleKey).tag(p) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "$%.2f", viewModel.aiTotals.totalCost))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text(summarySubtitle)
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
                            Text(formatTokens(src.inputTokens + src.outputTokens) + " tok")
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
                            Text(formatTokens(m.inputTokens + m.outputTokens) + " tok")
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }

            if viewModel.githubEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("section.github").font(.headline)
                    Text(String(format: NSLocalizedString("github.commits_repos %@ %@", comment: ""),
                                viewModel.githubTotals.totalCommits.formatted(),
                                viewModel.githubTotals.uniqueRepos.formatted()))
                        .font(.system(.body, design: .monospaced))
                    Text(String(format: NSLocalizedString("github.loc %@ %@", comment: ""),
                                formatLOC(viewModel.loc.additions),
                                formatLOC(viewModel.loc.deletions)))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if viewModel.githubTotals.totalCommits > 0 && !viewModel.topRepos.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("section.top_repos").font(.headline)
                        ForEach(viewModel.topRepos, id: \.self) { r in
                            HStack {
                                Text(repoShortName(r.repo))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("\(r.commits) c")
                                Text(formatLOC(r.additions) + " +")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("section.trend").font(.caption).foregroundStyle(.secondary)
                Sparkline(values: viewModel.sparklineSeries)
            }

            if viewModel.githubEnabled && viewModel.additionsSeries.contains(where: { $0 > 0 }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("section.trend_additions").font(.caption).foregroundStyle(.secondary)
                    Sparkline(values: viewModel.additionsSeries)
                }
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
    }

    private var summarySubtitle: String {
        let tokens = formatTokens(viewModel.aiTotals.totalInputTokens + viewModel.aiTotals.totalOutputTokens)
        if viewModel.githubEnabled {
            return "\(tokens) tokens • \(viewModel.githubTotals.totalCommits) commits"
        }
        return "\(tokens) tokens"
    }

    private func formatTokens(_ count: Int64) -> String {
        let value = Double(count)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", value / 1_000) }
        return "\(count)"
    }

    private func repoShortName(_ full: String) -> String {
        // owner/name → name. Если name слишком длинный, оставляем как есть.
        guard let slash = full.firstIndex(of: "/") else { return full }
        return String(full[full.index(after: slash)...])
    }

    private func formatLOC(_ count: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
