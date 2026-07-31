import SwiftUI

/// Цвета лимитов. У каждого провайдера свой цвет, и он не меняется никогда —
/// цвет здесь опознавательный знак, а не сигнал тревоги.
///
/// Раньше на порогах 70% и 90% цвет уходил в жёлтый и красный. От этого
/// отказались: три кольца в меню-баре идут подряд без подписей, и цвет — их
/// единственное отличие. Когда Codex краснел на 96%, ряд превращался в три
/// одинаковых пятна и переставал читаться. Насколько всё плохо, показывают
/// заполненность кольца и полоски в попапе.
enum LimitRingPalette {
    static let codexBlue = Color(red: 59/255, green: 130/255, blue: 246/255)
    /// Фирменный оранжевый Anthropic, осветлённый под тёмную капсулу.
    static let claudeOrange = Color(red: 232/255, green: 135/255, blue: 95/255)
    static let openCodeWhite = Color.white

    /// Нейтральный трек вместо «свой цвет с прозрачностью»: белое кольцо с белым
    /// треком в светлой теме меню-бара сливается с фоном.
    static let trackColor = Color.primary.opacity(0.15)
    /// Тонкий контур держит форму белого кольца на светлом фоне. На тёмном не виден.
    static let contourColor = Color.black.opacity(0.25)

    static func color(for provider: LimitProvider) -> Color {
        switch provider {
        case .codex:    return codexBlue
        case .claude:   return claudeOrange
        case .opencode: return openCodeWhite
        }
    }
}
