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

/// Левый блок: период, большая сумма, строка дельты, сабтайтлы.
/// Используется в Small, в левой половине Medium и в левой колонке Large — единообразно.
struct SummaryColumn: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(periodLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(String(format: "$%.2f", entry.aiCost))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if let delta = DropdownFormat.formatCostDelta(
                current: entry.aiCost,
                previous: entry.aiCostPrev,
                period: entry.period
            ) {
                HStack(spacing: 4) {
                    Text(delta.arrow + " " + delta.amount)
                        .foregroundStyle(delta.direction == .up ? .green : .red)
                    Text(NSLocalizedString(delta.labelKey, comment: ""))
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(DropdownFormat.tokens(entry.aiTokens)) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.githubEnabled {
                    Text(commitsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var periodLabel: LocalizedStringKey {
        switch entry.period {
        case .day: return "period.day"
        case .week: return "period.week"
        case .month: return "period.month"
        }
    }

    private var commitsText: String {
        let n = entry.commits
        let suffix = NSLocalizedString("widget.commits_suffix", comment: "")
        return "\(n) \(suffix)"
    }
}

struct SmallView: View {
    let entry: StatsEntry

    var body: some View {
        SummaryColumn(entry: entry)
            .padding(14)
    }
}

struct MediumView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SummaryColumn(entry: entry)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("section.top_models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if entry.topModels.isEmpty {
                    Text("label.no_data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(entry.topModels.prefix(4), id: \.self) { m in
                            ModelRow(model: m)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
    }
}

private struct ModelRow: View {
    let model: WidgetSnapshot.ModelEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(shortName)
                .font(.system(.caption, design: .default))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Text(String(format: "$%.2f", model.costUsd))
                .font(.system(.caption, design: .monospaced))
        }
    }

    /// claude-opus-4-7 → opus-4-7, claude-sonnet-4-6 → sonnet-4-6,
    /// codex-auto-review → codex-review (укоротили чтоб влезало).
    private var shortName: String {
        var s = model.model
        if s.hasPrefix("claude-") { s = String(s.dropFirst("claude-".count)) }
        if s.hasPrefix("claude-haiku-4-5") { s = "haiku-4-5" }
        return s
    }
}
