import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: DropdownViewModel
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $viewModel.period) {
                ForEach(Period.allCases) { p in Text(p.title).tag(p) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "$%.2f", viewModel.aiTotals.totalCost))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("\(formatTokens(viewModel.aiTotals.totalInputTokens + viewModel.aiTotals.totalOutputTokens)) tokens • \(viewModel.githubTotals.totalCommits) commits")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("AI Usage").font(.headline)
                if viewModel.bySource.isEmpty {
                    Text("no data yet").font(.caption).foregroundStyle(.secondary)
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
                Text("Top Models").font(.headline)
                if viewModel.topModels.isEmpty {
                    Text("no data yet").font(.caption).foregroundStyle(.secondary)
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

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub").font(.headline)
                Text("\(viewModel.githubTotals.totalCommits) commits across \(viewModel.githubTotals.uniqueRepos) repos")
                    .font(.system(.body, design: .monospaced))
                Text("+\(formatLOC(viewModel.loc.additions)) / -\(formatLOC(viewModel.loc.deletions)) lines")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Trend (last 14 days)").font(.caption).foregroundStyle(.secondary)
                Sparkline(values: viewModel.sparklineSeries)
            }

            Divider()

            HStack {
                Text("Last sync \(viewModel.lastSyncDescription)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }.buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func formatTokens(_ count: Int64) -> String {
        let value = Double(count)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", value / 1_000) }
        return "\(count)"
    }

    private func formatLOC(_ count: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
