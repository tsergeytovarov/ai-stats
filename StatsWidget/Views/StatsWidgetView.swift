import SwiftUI
import WidgetKit

struct StatsWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

struct SmallView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(periodLabel).font(.caption).foregroundStyle(.secondary)
            Text(String(format: "$%.2f", entry.aiCost))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(formatTokens(entry.aiTokens)) tokens")
                .font(.caption).foregroundStyle(.secondary)
            if entry.githubEnabled {
                Text("\(entry.commits) commits")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var periodLabel: LocalizedStringKey {
        switch entry.period {
        case .day: return "period.day"
        case .week: return "period.week"
        case .month: return "period.month"
        }
    }

    private func formatTokens(_ count: Int64) -> String {
        let value = Double(count)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", value / 1_000) }
        return "\(count)"
    }
}

struct MediumView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(spacing: 12) {
            SmallView(entry: entry)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("section.top_models").font(.caption).foregroundStyle(.secondary)
                if entry.topModels.isEmpty {
                    Text("label.no_data").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(entry.topModels.prefix(4), id: \.self) { m in
                        HStack {
                            Text(shortModel(m.model))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(String(format: "$%.2f", m.costUsd))
                                .font(.system(.caption, design: .monospaced))
                        }
                        .font(.caption)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private func shortModel(_ name: String) -> String {
        // claude-opus-4-7 → opus-4-7; gpt-5.5 → gpt-5.5
        if name.hasPrefix("claude-") { return String(name.dropFirst("claude-".count)) }
        return name
    }
}
