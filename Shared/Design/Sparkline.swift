import SwiftUI
import Charts

enum SparklineVariant {
    case ai
    case github

    var strokeColors: [Color] {
        switch self {
        case .ai:     return [BrandColor.pinkLight, BrandColor.pink]
        case .github: return [BrandColor.cyanLight, BrandColor.cyan]
        }
    }

    var fillTopColor: Color {
        switch self {
        case .ai:     return BrandColor.pinkLight.opacity(0.3)
        case .github: return BrandColor.cyanLight.opacity(0.28)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var variant: SparklineVariant = .ai

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("Day", item.offset), y: .value("Value", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [variant.fillTopColor, .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            LineMark(x: .value("Day", item.offset), y: .value("Value", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: variant.strokeColors, startPoint: .leading, endPoint: .trailing)
                )
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 36)
    }
}

extension Color {
    /// GitHub contribution heatmap green (#39d353). Оставлено для обратной совместимости.
    static let githubGreen = Color(red: 0x39 / 255.0, green: 0xd3 / 255.0, blue: 0x53 / 255.0)
}
