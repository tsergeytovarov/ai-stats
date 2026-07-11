import SwiftUI
import Charts

enum SparklineVariant {
    case ai

    var strokeColors: [Color] {
        switch self {
        case .ai:     return [BrandColor.pinkLight, BrandColor.pink]
        }
    }

    var fillTopColor: Color {
        switch self {
        case .ai:     return BrandColor.pinkLight.opacity(0.3)
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
