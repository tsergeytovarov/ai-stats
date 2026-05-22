import WidgetKit
import SwiftUI
import AppIntents
import GRDB

@main
struct StatsWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatsWidget()
    }
}

struct StatsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.sergeytovarov.aistats.widget",
            intent: PeriodConfigurationIntent.self,
            provider: StatsTimelineProvider()
        ) { entry in
            StatsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ai-stats")
        .description("AI usage и GitHub активность за выбранный период.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
