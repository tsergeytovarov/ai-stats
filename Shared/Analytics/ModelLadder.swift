import Foundation

/// Лестницы моделей и коэффициенты судьи (спека 5.3, порт констант из experiment2/3.py).
/// Классификация — по префиксу имени, специфичный раньше общего.
enum ModelLadder {

    /// Ступень модели в лестнице.
    enum Rung: Equatable {
        case frontier   // T0
        case middle     // средняя
        case small      // маленькая
    }

    // Порядок важен: специфичный префикс раньше общего (gpt-5.4-mini раньше gpt-5.4).
    private static let prefixRungs: [(prefix: String, rung: Rung)] = [
        ("gpt-5.4-mini", .small),
        ("gpt-5.6-sol", .frontier),
        ("gpt-5.6-terra", .middle),
        ("gpt-5.6-luna", .small),
        ("gpt-5.3-codex-spark", .small),
        ("claude-fable-", .frontier),
        ("claude-mythos-", .frontier),
        ("claude-opus-", .frontier),
        ("claude-sonnet-", .middle),
        ("claude-haiku-", .small),
        ("gpt-5.5", .frontier),
        ("gpt-5.4", .middle),
    ]

    /// Ступень по префиксу; nil — модель не распознана ни одним префиксом лестницы.
    /// Примечание: прото-`heur_tier` гейтит вердикт по `startswith(T0_PREFIXES)` —
    /// используем `isT0`, а не наличие ступени (см. `TurnCostCalculator`).
    static func rung(for model: String) -> Rung? {
        for (prefix, rung) in prefixRungs where model.hasPrefix(prefix) {
            return rung
        }
        return nil
    }

    /// Ход получает вердикт «мог быть дешевле» только для T0-моделей (frontier).
    static func isT0(_ model: String) -> Bool {
        rung(for: model) == .frontier
    }

    /// Целевая модель даунгрейда по heur_tier (1 — средняя, 2 — маленькая); nil для tier 0.
    static func targetModel(source: String, tier: Int) -> String? {
        switch (source, tier) {
        case ("claude-code", 1): return "claude-sonnet-4-6"
        case ("claude-code", 2): return "claude-haiku-4-5"
        case ("codex", 1): return "gpt-5.4"
        case ("codex", 2): return "gpt-5.4-mini"
        default: return nil
        }
    }

    /// Судейская доля экономии для страты tier 0 (n=79, калибровка 2026-07-11).
    static func judgeRatioT0(source: String) -> Double {
        switch source {
        case "claude-code": return 0.057
        case "codex": return 0.072
        default: return 0.0
        }
    }
}
