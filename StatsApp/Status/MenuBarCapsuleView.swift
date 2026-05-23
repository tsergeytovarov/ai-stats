import SwiftUI

struct MenuBarCapsuleView: View {
    let priceText: String   // "$1,602.78"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 11, weight: .semibold))
            Text(priceText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(
            LinearGradient(
                colors: [BrandColor.pink.opacity(0.25), BrandColor.cyan.opacity(0.25)],
                startPoint: .leading, endPoint: .trailing
            )
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }
}
