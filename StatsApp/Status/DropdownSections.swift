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

// MARK: - Expenses section

struct DropdownAISection: View {
    @ObservedObject var viewModel: DropdownViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Crumb(category: .ai, title: "Расходы", period: viewModel.period.localizedTitle)

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
                        Text(DropdownFormat.modelDisplayName(model: m.model, source: m.source))
                            .font(BrandFont.body)
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
