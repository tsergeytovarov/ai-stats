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

    /// Трек и контур подстраиваются под тему меню-бара, а не берутся одной
    /// константой: на светлом фоне белое кольцо OpenCode тонет, и проверка
    /// глазами это подтвердила. Цвета самих провайдеров при этом постоянные —
    /// подкручиваем только то, что их обрамляет.
    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Нейтральный трек вместо «свой цвет с прозрачностью»: белое кольцо с белым
    /// треком слилось бы с фоном. Основа у трека разная по темам — на тёмном
    /// меню-баре светлая, на светлом тёмная, иначе незаполненная часть кольца
    /// не читается ни в одной из них.
    static let trackColor = adaptive(dark: .white.withAlphaComponent(0.18),
                                     light: .black.withAlphaComponent(0.28))

    /// Контур держит форму кольца. На тёмном фоне почти не виден, на светлом —
    /// единственное, что отделяет белое кольцо OpenCode от меню-бара, поэтому
    /// там он вдвое плотнее.
    static let contourColor = adaptive(dark: .black.withAlphaComponent(0.25),
                                       light: .black.withAlphaComponent(0.55))

    static func color(for provider: LimitProvider) -> Color {
        switch provider {
        case .codex:    return codexBlue
        case .claude:   return claudeOrange
        case .opencode: return openCodeWhite
        }
    }
}
