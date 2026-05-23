import Foundation

// MARK: - delta content types

enum DeltaDirection: Equatable {
    case up
    case down
}

struct CostDeltaContent: Equatable {
    let arrow: String       // "▲" или "▼"
    let amount: String      // "+$27.60" или "−$50.00"
    let labelKey: String    // ключ для NSLocalizedString
    let direction: DeltaDirection
}

struct RankDeltaContent: Equatable {
    enum Kind: Equatable {
        case change(magnitude: Int, direction: DeltaDirection)
        case new
    }
    let kind: Kind
}

// MARK: - helpers (shared between sections and widgets)

enum DropdownFormat {
    static func tokens(_ count: Int64) -> String {
        let value = Double(count)
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", value / 1_000) }
        return "\(count)"
    }

    static func loc(_ count: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// "owner/name" → "name"
    static func repoShortName(_ full: String) -> String {
        guard let slash = full.firstIndex(of: "/") else { return full }
        return String(full[full.index(after: slash)...])
    }

    static func formatCostDelta(current: Double, previous: Double, period: Period) -> CostDeltaContent? {
        guard current > 0 else { return nil }
        let diff = current - previous
        // Скрываем дельту, если разница меньше копейки — после округления до $0.00 показывать стрелку бессмысленно.
        guard abs(diff) >= 0.005 else { return nil }
        let direction: DeltaDirection = diff > 0 ? .up : .down
        let arrow = diff > 0 ? "▲" : "▼"
        let sign = diff > 0 ? "+" : "−"
        let amount = String(format: "%@$%.2f", sign, abs(diff))
        let labelKey: String
        switch period {
        case .day:   labelKey = "delta.vs_yesterday"
        case .week:  labelKey = "delta.vs_prev_week"
        case .month: labelKey = "delta.vs_prev_month"
        }
        return CostDeltaContent(arrow: arrow, amount: amount, labelKey: labelKey, direction: direction)
    }

    static func formatRankDelta(current: Int, previous: Int?) -> RankDeltaContent? {
        guard let previous else {
            return RankDeltaContent(kind: .new)
        }
        let diff = previous - current   // подъём в рейтинге = current уменьшился = diff положительный
        guard diff != 0 else { return nil }
        let direction: DeltaDirection = diff > 0 ? .up : .down
        return RankDeltaContent(kind: .change(magnitude: abs(diff), direction: direction))
    }
}
