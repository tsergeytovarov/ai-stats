import SwiftUI

/// Кольцо лимита одного провайдера. Заливка — по ближайшему к сбросу окну,
/// цвет — по худшему окну. Нет данных — серый пунктир.
struct LimitRingView: View {
    let provider: LimitProvider
    let limits: ProviderLimits?
    var diameter: CGFloat = 10
    var lineWidth: CGFloat = 2

    private var fillFraction: Double {
        guard let percent = limits?.ringWindow?.usedPercent else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    private var hasData: Bool {
        guard let limits, limits.status != .unconfigured, limits.status != .unavailable
        else { return false }
        return limits.ringWindow != nil
    }

    private var strokeColor: Color {
        guard let worst = limits?.worstPercent else { return .secondary }
        return LimitRingPalette.color(for: provider,
                                      severity: LimitThresholds.severity(worstPercent: worst))
    }

    var body: some View {
        ZStack {
            if hasData {
                Circle()
                    .stroke(LimitRingPalette.trackColor, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fillFraction)
                    .stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .stroke(LimitRingPalette.contourColor, lineWidth: 0.5)
            } else {
                Circle()
                    .stroke(Color.secondary.opacity(0.5),
                            style: StrokeStyle(lineWidth: lineWidth, dash: [2, 2]))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(provider.displayTitle))
    }
}
