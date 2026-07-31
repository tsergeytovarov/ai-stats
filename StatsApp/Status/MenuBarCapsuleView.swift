import SwiftUI

/// Геометрия ряда колец в капсуле. Единственный источник правды: и вёрстка, и
/// расчёт ширины NSStatusItem берут числа отсюда. Раньше они были заданы дважды —
/// здесь и в контроллере — и разъехались: правый край последнего кольца уезжал
/// под обрезку.
enum LimitRingLayout {
    static let diameter: CGFloat = 10
    static let lineWidth: CGFloat = 2
    /// Обводка центрируется на контуре круга, то есть половина её толщины
    /// выходит за номинальный диаметр с каждой стороны. При spacing 3 разрыв
    /// съедала как раз она, и три кольца слипались в одно пятно.
    static let spacing: CGFloat = 5
    static let leadingPadding: CGFloat = 3

    /// Ширина всего ряда колец вместе с отступом от цены.
    static var totalWidth: CGFloat {
        let count = CGFloat(LimitProvider.allCases.count)
        guard count > 0 else { return 0 }
        return leadingPadding + count * diameter + (count - 1) * spacing
    }
}

struct MenuBarCapsuleView: View {
    let priceText: String   // "$1,602.78"
    var limits: [LimitProvider: ProviderLimits] = [:]

    /// Кольца прячем, если ни по одному провайдеру нет данных: три серых
    /// пунктира в меню-баре — мусор, а не информация.
    private var showsRings: Bool {
        Self.showsRings(for: limits)
    }

    var body: some View {
        HStack(spacing: 4) {
            MiniEmberView(size: 12)
            Text(priceText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
            if showsRings {
                HStack(spacing: LimitRingLayout.spacing) {
                    ForEach(LimitProvider.allCases, id: \.self) { provider in
                        LimitRingView(provider: provider, limits: limits[provider])
                    }
                }
                .padding(.leading, LimitRingLayout.leadingPadding)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(
                colors: [BrandColor.pink.opacity(0.25), BrandColor.cyan.opacity(0.25)],
                startPoint: .leading, endPoint: .trailing
            )
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
    }
}

extension MenuBarCapsuleView {
    /// Общее условие показа колец — используется и вью, и StatusItemController
    /// при расчёте детерминированной ширины capsule. Один источник правды,
    /// чтобы не завести второе (расходящееся) определение «есть ли данные».
    static func showsRings(for limits: [LimitProvider: ProviderLimits]) -> Bool {
        LimitProvider.allCases.contains { limits[$0]?.ringWindow != nil }
    }
}
