import SwiftUI

// MARK: - CategoryPill

struct CategoryPill: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(BrandFont.pillBody)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.6))
                .background(
                    Group {
                        if isActive {
                            LinearGradient(
                                colors: [BrandColor.pinkLight, BrandColor.pink],
                                startPoint: .top, endPoint: .bottom
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: BrandRadius.pill)
                                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                                    .blendMode(.plusLighter)
                            )
                        } else {
                            Color.clear
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: BrandRadius.pill, style: .continuous))
                .shadow(color: isActive ? BrandColor.pink.opacity(0.45) : .clear, radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - PeriodSegment

struct PeriodSegment: View {
    @Binding var selection: Period

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Period.allCases) { p in
                Button {
                    selection = p
                } label: {
                    Text(p.shortKey)
                        .font(BrandFont.pillPeriod)
                        .frame(minWidth: 16)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 9)
                        .foregroundStyle(p == selection ? Color(red: 0, green: 40/255, blue: 46/255) : Color.white.opacity(0.55))
                        .background(
                            Group {
                                if p == selection {
                                    LinearGradient(colors: [BrandColor.cyanLight, BrandColor.cyan], startPoint: .top, endPoint: .bottom)
                                } else { Color.clear }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.pill, style: .continuous))
                        .shadow(color: p == selection ? BrandColor.cyan.opacity(0.45) : .clear, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: BrandRadius.pill, style: .continuous))
    }
}

// MARK: - FloatingIsland

struct FloatingIsland: View {
    @Binding var section: DropdownSection
    @Binding var period: Period

    var body: some View {
        HStack(spacing: 2) {
            CategoryPill(title: NSLocalizedString("section.ai", comment: ""),
                         isActive: section == .ai) { section = .ai }
            CategoryPill(title: NSLocalizedString("section.github", comment: ""),
                         isActive: section == .github) { section = .github }
            CategoryPill(title: NSLocalizedString("section.friends", comment: ""),
                         isActive: section == .leaderboard) { section = .leaderboard }

            Rectangle().fill(Color.white.opacity(0.18))
                .frame(width: 0.5, height: 18)
                .padding(.horizontal, 4)

            PeriodSegment(selection: $period)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.pill, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: BrandRadius.pill, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.pill, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.65), radius: 16, x: 0, y: 12)
        .shadow(color: BrandColor.pink.opacity(0.14), radius: 14, x: 0, y: 0)
    }
}
