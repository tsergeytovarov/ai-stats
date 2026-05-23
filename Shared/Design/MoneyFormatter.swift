import Foundation

/// Форматтеры денег для разных surfaces.
/// - Поповер: с копейками.
/// - Виджеты: целые доллары.
enum MoneyFormatter {
    private static let group: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.groupingSeparator = "\u{00A0}"  // non-breaking space
        f.maximumFractionDigits = 0
        return f
    }()

    private static let groupCents: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.groupingSeparator = "\u{00A0}"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// "$1\u{00A0}603" — для виджетов (округление до целого).
    static func widget(_ value: Double) -> String {
        // Явный .rounded() нужен: NumberFormatter использует banker's rounding (0.5 → 0).
        let rounded = value.rounded()
        let s = group.string(from: NSNumber(value: rounded)) ?? "0"
        return "$" + s
    }

    /// "+$390" / "−$50" — дельта в виджетах.
    static func widgetDelta(_ value: Double) -> String {
        let rounded = value.rounded()
        if rounded == 0 { return "$0" }
        let absVal = group.string(from: NSNumber(value: Swift.abs(rounded))) ?? "0"
        let sign = rounded > 0 ? "+" : "−"   // U+2212 minus
        return "\(sign)$\(absVal)"
    }

    /// "$1\u{00A0}602.78" — для поповера.
    static func popover(_ value: Double) -> String {
        let s = groupCents.string(from: NSNumber(value: value)) ?? "0.00"
        return "$" + s
    }
}
