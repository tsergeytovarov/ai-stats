import SwiftUI

/// 3-слойная поверхность: Liquid Glass (Tahoe) + внутренний brand-градиент + content.
/// Идентичность держится независимо от обоев.
///
/// Использование:
/// ```swift
/// VStack { ... }
///     .brandSurface()
/// ```
struct BrandSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let tintIntensity: Double  // 0...1, дефолт 1.0
    let content: Content

    init(
        cornerRadius: CGFloat = BrandRadius.surface,
        tintIntensity: Double = 1.0,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tintIntensity = tintIntensity
        self.content = content()
    }

    var body: some View {
        ZStack {
            // Layer 1: base glass (Tahoe API)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(SurfaceColor.base)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )

            // Layer 2: brand overlay — radial pink TL + radial cyan BR
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            SurfaceColor.tintPink.opacity(tintIntensity),
                            .clear
                        ]),
                        center: UnitPoint(x: 0.15, y: 0.0),
                        startRadius: 0,
                        endRadius: 280
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            SurfaceColor.tintCyan.opacity(tintIntensity),
                            .clear
                        ]),
                        center: UnitPoint(x: 1.0, y: 1.0),
                        startRadius: 0,
                        endRadius: 320
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // Layer 3: content
            content
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(SurfaceColor.borderGlass, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 16)
    }
}

extension View {
    /// Применяет brand-поверхность (стекло + brand overlay) ко всему контенту.
    func brandSurface(cornerRadius: CGFloat = BrandRadius.surface, tintIntensity: Double = 1.0) -> some View {
        BrandSurface(cornerRadius: cornerRadius, tintIntensity: tintIntensity) {
            self
        }
    }
}
