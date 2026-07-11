import SwiftUI
import WidgetKit

struct LargeView: View {
    let entry: StatsEntry

    var body: some View {
        Group {
            if entry.isPlaceholder {
                WidgetPlaceholderView()
            } else {
                content
            }
        }
        .containerBackground(for: .widget) { burnWidgetBackground() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Top row
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Crumb(category: .ai, title: "AI", period: entry.period.localizedTitle)
                    HeroNumber(MoneyFormatter.widget(entry.aiCost), font: BrandFont.widgetHeroLarge, variant: .pink)
                        .padding(.top, 4)
                    if entry.aiCostPrev > 0 {
                        Text(MoneyFormatter.widgetDelta(entry.aiCost - entry.aiCostPrev) + " " + NSLocalizedString("delta.vs_yesterday", comment: ""))
                            .font(BrandFont.caption)
                            .foregroundStyle(BrandColor.cyanLight)
                            .padding(.top, 2)
                    }
                    Text(DropdownFormat.tokens(entry.aiTokens) + " tok")
                        .font(.system(size: 10))
                        .foregroundStyle(BrandColor.cyanLight.opacity(0.75))
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                }
                .padding(14)

                Rectangle().fill(SurfaceColor.dividerSubtle).frame(width: 0.5)

                VStack(alignment: .leading, spacing: 0) {
                    Text("section.top_models").font(BrandFont.lbl).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(BrandColor.cyanLight.opacity(0.7)).padding(.bottom, 4)
                    ForEach(entry.topModels.prefix(3), id: \.model) { m in
                        HStack {
                            Text(m.model).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(MoneyFormatter.widget(m.costUsd))
                                .font(.system(size: 11)).monospacedDigit()
                                .foregroundStyle(.white.opacity(0.8))
                        }.padding(.vertical, 2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Rectangle().fill(SurfaceColor.dividerSubtle).frame(height: 0.5)

            // Строка советника (спека 2.3) вместо лидерборда. Скрыта, пока
            // расчёта не было или данных мало (advisorLine == nil).
            Group {
                if let line = entry.advisorLine {
                    Text(line)
                        .font(BrandFont.caption)
                        .foregroundStyle(BrandColor.cyanLight)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
