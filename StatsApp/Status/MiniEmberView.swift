import SwiftUI

/// Mini-ember для menu bar capsule. Та же метафора, что и app-иконка в Dock,
/// уменьшенная до глифа высотой ≈12pt.
///
/// Реализация — pure SwiftUI: Circle + RadialGradient (highlight в top-left
/// сегменте) + двойная shadow для ambient bloom. Цвета берутся из BrandColor
/// токенов, чтобы редизайн палитры подхватывался автоматически.
struct MiniEmberView: View {
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white,                                                       location: 0.00),
                        .init(color: Color(red: 1.0,   green: 0xE1/255.0, blue: 0xEC/255.0),       location: 0.06),
                        .init(color: Color(red: 1.0,   green: 0x9B/255.0, blue: 0xC1/255.0),       location: 0.16),
                        .init(color: BrandColor.pinkLight,                                          location: 0.32),
                        .init(color: BrandColor.pink,                                               location: 0.52),
                        .init(color: Color(red: 0xC0/255.0, green: 0x15/255.0, blue: 0x58/255.0),  location: 0.78),
                        .init(color: Color(red: 0x5D/255.0, green: 0x08/255.0, blue: 0x24/255.0),  location: 1.00),
                    ]),
                    center: UnitPoint(x: 0.34, y: 0.28),
                    startRadius: 0,
                    endRadius: size * 0.55
                )
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: BrandColor.pink.opacity(0.85), radius: size * 0.5)
            .shadow(color: BrandColor.cyan.opacity(0.35), radius: size * 1.0)
    }
}

#Preview("MiniEmber on dark") {
    HStack(spacing: 12) {
        MiniEmberView(size: 12)
        MiniEmberView(size: 16)
        MiniEmberView(size: 24)
    }
    .padding(20)
    .background(Color(red: 0x1A/255.0, green: 0x1A/255.0, blue: 0x20/255.0))
}
