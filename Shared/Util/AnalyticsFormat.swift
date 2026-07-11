import Foundation

/// Форматтер токенов для карточки «Аналитика» (спека 6). Отличается от
/// `DropdownFormat.tokens` («%.1fM»/«%.0fk»), который остаётся для вкладки «Расходы».
enum AnalyticsFormat {
    /// ≥1 млрд — «1.92 млрд ток» (два знака); ≥1 млн — «412 млн ток» (целые);
    /// ≥1 тыс — «512 тыс ток» (целые); меньше — «312 ток».
    static func tokens(_ count: Int64) -> String {
        let v = Double(count)
        if v >= 1_000_000_000 { return String(format: "%.2f млрд ток", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.0f млн ток", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0f тыс ток", v / 1_000) }
        return "\(count) ток"
    }
}
