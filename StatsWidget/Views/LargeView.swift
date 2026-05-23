import SwiftUI
import WidgetKit

struct LargeView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leftColumn
            Divider()
            LeaderboardColumn(slice: entry.leaderboard)
        }
        .padding(14)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryColumn(entry: entry)

            if !entry.topModels.isEmpty {
                Text("section.top_models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.topModels.prefix(3), id: \.self) { ModelRow(model: $0) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Leaderboard

struct LeaderboardColumn: View {
    let slice: WidgetSnapshot.LeaderboardSlice?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("section.leaderboard")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if let slice {
            if slice.entries.isEmpty {
                Text("widget.leaderboard.empty")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(slice.entries, id: \.rank) { LeaderboardRow(entry: $0) }
                    if let me = slice.meBelow {
                        Text("⋯").font(.caption2).foregroundStyle(.secondary)
                        LeaderboardRow(entry: me)
                    }
                }
            }
        } else {
            Text("widget.leaderboard.no_account")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct LeaderboardRow: View {
    let entry: WidgetSnapshot.LeaderboardSlice.Entry

    var body: some View {
        HStack(spacing: 4) {
            Text("\(entry.rank).")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)

            rankDelta
                .frame(width: 30, alignment: .leading)

            Text(entry.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(DropdownFormat.tokens(entry.tokensTotal))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
        .background(entry.isMe ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private var rankDelta: some View {
        if let content = DropdownFormat.formatRankDelta(current: entry.rank, previous: entry.previousRank) {
            switch content.kind {
            case .new:
                Text(NSLocalizedString("delta.new", comment: ""))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .change(let magnitude, let direction):
                Text("\(direction == .up ? "▲" : "▼")\(magnitude)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(direction == .up ? .green : .red)
            }
        } else {
            Text(" ").font(.system(.caption2, design: .monospaced))
        }
    }
}
