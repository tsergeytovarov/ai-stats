import SwiftUI
import Charts

struct Sparkline: View {
    let values: [Double]
    var tint: Color = .accentColor

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Day", item.offset), y: .value("Value", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 36)
    }
}

extension Color {
    /// GitHub contribution heatmap green (#39d353).
    static let githubGreen = Color(red: 0x39 / 255.0, green: 0xd3 / 255.0, blue: 0x53 / 255.0)
}
