import Foundation

/// Тексты секции лимитов. Отдельно от вью — чтобы тестировались без SwiftUI.
enum LimitFormat {

    static func percent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return "\(Int(rounded.rounded()))%"
        }
        return String(format: "%.1f%%", rounded)
    }

    static func window(minutes: Int) -> String {
        switch minutes {
        case 300:   return "5 часов"
        case 1440:  return "24 часа"
        case 10080: return "неделя"
        case 43200: return "месяц"
        default:
            let hours = minutes / 60
            return hours > 0 ? "\(hours) ч" : "\(minutes) мин"
        }
    }

    /// nil — времени сброса нет или оно уже в прошлом. Показывать «сброс через
    /// -3м» нельзя: это не информация, а баг на экране.
    static func resetsIn(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return nil }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "сброс через \(days)д \(hours)ч" }
        if hours > 0 { return "сброс через \(hours)ч \(minutes)м" }
        return "сброс через \(minutes)м"
    }

    static func fetchedAt(_ date: Date?) -> String {
        guard let date else { return "нет данных" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "данные на \(formatter.string(from: date))"
    }

    /// Строка действия для состояний, где без человека не обойтись. Для
    /// остальных nil — рисуем обычные полоски.
    static func actionText(for provider: LimitProvider, status: LimitStatus) -> String? {
        switch status {
        case .unauthorized:
            return provider == .opencode
                ? "\(provider.displayTitle): cookie протухла, обнови в настройках"
                : "\(provider.displayTitle): нужен вход заново"
        case .unconfigured:
            return "\(provider.displayTitle): вставь cookie в настройках"
        case .unavailable:
            return "\(provider.displayTitle): источник недоступен"
        case .ok, .stale, .throttled:
            return nil
        }
    }
}
