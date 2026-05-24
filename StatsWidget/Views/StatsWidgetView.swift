import SwiftUI
import WidgetKit

struct StatsWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

// MARK: - Small

struct SmallView: View {
    let entry: StatsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Crumb(category: .ai, title: "AI", period: entry.period.localizedTitle)

            HeroNumber(MoneyFormatter.widget(entry.aiCost),
                       font: BrandFont.widgetHeroSmall,
                       variant: .pink)
                .padding(.top, 6)

            if entry.aiCostPrev > 0 {
                Text(MoneyFormatter.widgetDelta(entry.aiCost - entry.aiCostPrev))
                    .font(BrandFont.caption)
                    .foregroundStyle(BrandColor.cyanLight)
                    .padding(.top, 2)
            }

            Text(DropdownFormat.tokens(entry.aiTokens) + " tok · \(entry.commits) c")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BrandColor.cyanLight.opacity(0.75))
                .padding(.top, 2)

            Spacer(minLength: 4)

            Sparkline(values: [], variant: .ai)
                .frame(height: 22)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            ZStack {
                Color(red: 20/255, green: 8/255, blue: 30/255)
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(red: 1.0, green: 45/255, blue: 109/255).opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.7)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Color(red: 0, green: 184/255, blue: 230/255).opacity(0.45), location: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

// MARK: - Medium

struct MediumView: View {
    let entry: StatsEntry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Crumb(category: .ai, title: "AI", period: entry.period.localizedTitle)
                HeroNumber(MoneyFormatter.widget(entry.aiCost), font: BrandFont.widgetHeroMedium, variant: .pink)
                    .padding(.top, 4)
                if entry.aiCostPrev > 0 {
                    Text(MoneyFormatter.widgetDelta(entry.aiCost - entry.aiCostPrev) + " " + NSLocalizedString("delta.vs_yesterday", comment: ""))
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.cyanLight)
                        .padding(.top, 2)
                }
                Text(DropdownFormat.tokens(entry.aiTokens) + " tok · \(entry.commits) c")
                    .font(.system(size: 10))
                    .foregroundStyle(BrandColor.cyanLight.opacity(0.75))
                    .padding(.top, 2)
                Spacer(minLength: 0)
                Sparkline(values: [], variant: .ai).frame(height: 22)
            }
            .padding(14)

            Rectangle().fill(SurfaceColor.dividerSubtle).frame(width: 0.5)

            VStack(alignment: .leading, spacing: 0) {
                Text("section.top_models")
                    .font(BrandFont.lbl).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(BrandColor.cyanLight.opacity(0.7))
                    .padding(.bottom, 4)
                ForEach(entry.topModels.prefix(4), id: \.model) { m in
                    HStack {
                        Text(m.model).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(MoneyFormatter.widget(m.costUsd))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.vertical, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .containerBackground(for: .widget) {
            ZStack {
                Color(red: 20/255, green: 8/255, blue: 30/255)
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(red: 1.0, green: 45/255, blue: 109/255).opacity(0.55), location: 0),
                        .init(color: .clear, location: 0.7)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.3),
                        .init(color: Color(red: 0, green: 184/255, blue: 230/255).opacity(0.45), location: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}
