import SwiftUI
import WidgetKit

struct LargeView: View {
    let entry: StatsEntry

    var body: some View {
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
                    Text(DropdownFormat.tokens(entry.aiTokens) + " tok · \(entry.commits) c")
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

            // Sparkline middle
            VStack(alignment: .leading, spacing: 4) {
                Text("section.trend")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Sparkline(values: [], variant: .ai).frame(height: 24)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Rectangle().fill(SurfaceColor.dividerSubtle).frame(height: 0.5)

            // Leaderboard bottom
            VStack(alignment: .leading, spacing: 0) {
                Text(NSLocalizedString("section.leaderboard", comment: "")
                     + " · " + entry.period.localizedTitle)
                    .font(BrandFont.lbl).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(BrandColor.cyanLight.opacity(0.7))
                    .padding(.bottom, 4)

                if let board = entry.leaderboard, !board.entries.isEmpty {
                    ForEach(Array(board.entries.prefix(4).enumerated()), id: \.offset) { idx, peer in
                        FriendRow(rank: idx + 1, name: peer.displayName,
                                  valueText: DropdownFormat.tokens(peer.tokensTotal),
                                  isMe: peer.isMe,
                                  avatarData: WidgetSnapshotIO.readAvatar(friendCode: peer.friendCode))
                    }
                } else {
                    Text("widget.leaderboard.empty")
                        .font(BrandFont.caption).foregroundStyle(TextColor.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
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
