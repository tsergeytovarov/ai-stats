import SwiftUI

enum HeroVariant {
    case pink   // AI
    case cyan   // GitHub
}

/// Главное число поповера/виджета с градиентным fill.
struct HeroNumber: View {
    let text: String
    let font: Font
    let variant: HeroVariant

    init(_ text: String, font: Font = BrandFont.displayXXL, variant: HeroVariant = .pink) {
        self.text = text
        self.font = font
        self.variant = variant
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(gradient)
    }

    private var gradient: LinearGradient {
        let colors: [Color]
        switch variant {
        case .pink:
            colors = [.white, Color(red: 1.0, green: 212/255, blue: 227/255)]
        case .cyan:
            colors = [.white, Color(red: 212/255, green: 243/255, blue: 1.0)]
        }
        return LinearGradient(
            gradient: Gradient(stops: [
                .init(color: colors[0], location: 0.3),
                .init(color: colors[1], location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// "28 коммитов" — число + единица рядом.
struct HeroNumberWithUnit: View {
    let number: String
    let unit: String   // "коммитов", "репозиториев" — локализовано на месте использования

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HeroNumber(number, font: .system(size: 56, weight: .bold).monospacedDigit(), variant: .cyan)
            Text(unit).font(BrandFont.unitL).foregroundStyle(BrandColor.cyanLight.opacity(0.85))
        }
    }
}
