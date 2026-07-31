import SwiftUI

/// Цвета лимитов. Фирменный цвет провайдера виден только пока всё спокойно; на
/// порогах он уступает жёлтому и красному — в этот момент важно не «кто», а
/// «сколько осталось».
enum LimitRingPalette {
    static let codexBlue = Color(red: 59/255, green: 130/255, blue: 246/255)
    /// Фирменный оранжевый Anthropic, осветлённый под тёмную капсулу.
    static let claudeOrange = Color(red: 232/255, green: 135/255, blue: 95/255)
    static let openCodeWhite = Color.white
    static let warningYellow = Color(red: 255/255, green: 196/255, blue: 61/255)

    /// Нейтральный трек вместо «свой цвет с прозрачностью»: белое кольцо с белым
    /// треком в светлой теме меню-бара сливается с фоном.
    static let trackColor = Color.primary.opacity(0.15)
    /// Тонкий контур держит форму белого кольца на светлом фоне. На тёмном не виден.
    static let contourColor = Color.black.opacity(0.25)

    static func color(for provider: LimitProvider, severity: LimitSeverity) -> Color {
        switch severity {
        case .critical: return BrandColor.danger
        case .warning:  return warningYellow
        case .calm:
            switch provider {
            case .codex:    return codexBlue
            case .claude:   return claudeOrange
            case .opencode: return openCodeWhite
            }
        }
    }
}
