import SwiftUI

/// Brand colors из spec'а 2026-05-23-redesign-design.md.
enum BrandColor {
    /// #FF2D6D — primary brand
    static let pink = Color(red: 255/255, green: 45/255, blue: 109/255)
    /// #FF5FA0 — top gradient stop для активных pill и hero number
    static let pinkLight = Color(red: 255/255, green: 95/255, blue: 160/255)
    /// #00B8E6 — secondary brand
    static let cyan = Color(red: 0, green: 184/255, blue: 230/255)
    /// #4FE6FF — light cyan для accent и gradient
    static let cyanLight = Color(red: 79/255, green: 230/255, blue: 255/255)
    /// #00FF9D — success
    static let success = Color(red: 0, green: 255/255, blue: 157/255)
    /// #FF453A — danger
    static let danger = Color(red: 255/255, green: 69/255, blue: 58/255)
}

/// Surface colors (полупрозрачные подложки и оверлеи).
enum SurfaceColor {
    /// rgba(20,8,30,0.55) — base подложка стекла
    static let base = Color(red: 20/255, green: 8/255, blue: 30/255).opacity(0.55)
    /// Pink tint для overlay top-left
    static let tintPink = BrandColor.pink.opacity(0.42)
    /// Cyan tint для overlay bottom-right
    static let tintCyan = BrandColor.cyan.opacity(0.32)
    /// rgba(255,255,255,0.22) — edge stroke
    static let borderGlass = Color.white.opacity(0.22)
    /// rgba(255,255,255,0.08) — внутренние разделители
    static let dividerSubtle = Color.white.opacity(0.08)
}

/// Text colors (поверх стекла).
enum TextColor {
    /// чисто-белый
    static let primary = Color.white
    /// 70% — метаданные
    static let secondary = Color.white.opacity(0.7)
    /// 50% — sync timestamp, лейблы 4-го уровня
    static let muted = Color.white.opacity(0.5)
    /// pink lighter для AI crumb
    static let crumbAI = Color(red: 255/255, green: 143/255, blue: 184/255).opacity(0.9)
    /// cyan для GitHub crumb
    static let crumbGitHub = BrandColor.cyanLight.opacity(0.9)
    /// нейтрал для Друзей
    static let crumbFriends = Color.white.opacity(0.7)
}

/// Font tokens — все system, SF Pro Display для display.*, SF Pro Text для остального.
enum BrandFont {
    static let displayXXL = Font.system(size: 44, weight: .bold, design: .default).monospacedDigit()
    static let displayXL = Font.system(size: 46, weight: .bold, design: .default).monospacedDigit()
    static let displayL = Font.system(size: 38, weight: .bold, design: .default).monospacedDigit()
    static let displayM = Font.system(size: 30, weight: .bold, design: .default).monospacedDigit()

    static let unitL = Font.system(size: 18, weight: .semibold)
    static let delta = Font.system(size: 12, weight: .semibold).monospacedDigit()
    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .medium)
    static let crumb = Font.system(size: 11, weight: .semibold)
    static let lbl = Font.system(size: 10, weight: .semibold)
    static let pillBody = Font.system(size: 11, weight: .semibold)
    static let pillPeriod = Font.system(size: 10, weight: .semibold)
}

/// Spacing — 4pt grid.
enum BrandSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 22

    /// Резерв снизу popover'а под floating island (~ 46 + 32 воздуха).
    static let islandClearance: CGFloat = 78
    /// Островок offset от bottom edge.
    static let islandBottomOffset: CGFloat = 14
}

/// Radii.
enum BrandRadius {
    static let surface: CGFloat = 22
    static let pill: CGFloat = 999       // capsule
    static let button: CGFloat = 9
    static let field: CGFloat = 10
}
