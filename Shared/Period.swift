import Foundation

/// Период для агрегации статистики. Используется в приложении и в виджете.
enum Period: String, CaseIterable, Identifiable, Codable {
    case day, week, month
    var id: String { rawValue }
    var lookbackDays: Int {
        switch self {
        case .day: return 0
        case .week: return 6
        case .month: return 29
        }
    }
    var localizedTitle: String {
        NSLocalizedString("period.\(rawValue)", comment: "")
    }
    var shortKey: String {
        switch self {
        case .day: return NSLocalizedString("period.short.day", comment: "")
        case .week: return NSLocalizedString("period.short.week", comment: "")
        case .month: return NSLocalizedString("period.short.month", comment: "")
        }
    }
}
