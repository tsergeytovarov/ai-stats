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
}
