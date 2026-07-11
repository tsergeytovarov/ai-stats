import SwiftUI

enum CrumbCategory: Equatable {
    case ai

    var color: Color {
        switch self {
        case .ai: return TextColor.crumbAI
        }
    }
}

/// "AI · Сегодня" — uppercase, tracked, цветной по категории.
struct Crumb: View {
    let category: CrumbCategory
    let title: String
    let period: String   // локализованный «Сегодня» / «Неделя» / «Месяц»

    var body: some View {
        Text("\(title) · \(period)")
            .font(BrandFont.crumb)
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(category.color)
    }
}
