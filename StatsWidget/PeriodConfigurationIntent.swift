import AppIntents

struct PeriodConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Period"
    static var description = IntentDescription("Choose which period the widget displays.")

    @Parameter(title: "Period", default: PeriodKind.day)
    var period: PeriodKind
}

enum PeriodKind: String, AppEnum {
    case day, week, month

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static var caseDisplayRepresentations: [PeriodKind: DisplayRepresentation] = [
        .day: DisplayRepresentation(title: "Day"),
        .week: DisplayRepresentation(title: "Week"),
        .month: DisplayRepresentation(title: "Month"),
    ]

    var sharedPeriod: Period {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        }
    }
}
