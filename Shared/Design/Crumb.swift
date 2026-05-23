import SwiftUI

enum CrumbCategory: Equatable {
    case ai, github, friends

    var color: Color {
        switch self {
        case .ai: return TextColor.crumbAI
        case .github: return TextColor.crumbGitHub
        case .friends: return TextColor.crumbFriends
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
