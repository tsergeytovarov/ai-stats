import Foundation

/// Value-модель карточки «Аналитика» за фиксированное окно 30 дней.
/// Строится `AnalyticsCardBuilder` из `analytics_turns`/`analytics_rate_limits`.
/// Шпаргалка моделей не входит в карточку — её отдаёт `ModelGuide` (C6),
/// UI композирует их вместе.
struct AnalyticsCard: Equatable {

    enum State: Equatable {
        case noData        // ходов в окне нет вообще
        case tooFewData    // <50 ходов суммарно по обоим источникам
        case ready         // карточка собрана
    }

    /// Сводка по источнику (Codex / Claude Code).
    struct SourceSummary: Equatable {
        var source: String            // "codex" | "claude-code"
        var displayName: String       // "Codex" | "Claude Code"
        var tokens: Int64             // input+cache_read+cc5m+cc1h+output (с кэшем!)
        var costUsd: Double
        var expSavedUsd: Double
        /// «% объёма» в долларах: Σexp_saved/Σcost_usd × 100. nil при costUsd == 0.
        var leakPct: Double?
        /// Codex: средний недельный % лимита (Σэпох / (30/7)). Claude: nil.
        var avgWeekLimitPct: Double?
        /// Codex: суммарный расход лимита за месяц (Σэпох, п.п.). Claude: nil.
        var monthLimitPct: Double?
    }

    /// Модель в топе по использованию (токенам за окно).
    struct ModelUsage: Equatable {
        var model: String
        var tokens: Int64             // input+cache_read+cc5m+cc1h+output (с кэшем)
    }

    /// Кластер-утечка (топ-3 по экономии).
    struct LeakCluster: Equatable {
        var source: String            // "codex" | "claude-code"
        var key: String               // нормализованный ключ (lower, ≤60 / спецключ)
        var title: String             // отображаемый заголовок
        var nTurns: Int
        var model: String             // доминирующая по экономии модель
        var expSavedUsd: Double       // ≈$/мес
        var adviceText: String
    }

    var state: State
    var rangeStart: Date
    var rangeEnd: Date
    var sources: [SourceSummary]
    /// Топ моделей по токенам за окно (не по деньгам!), убыв., ≤6.
    var topModelsByTokens: [ModelUsage]
    var leaks: [LeakCluster]
    /// Σexp_saved по обоим источникам (для leakUsdPerMonth виджета).
    var totalExpSavedUsd: Double
    /// Заголовок топ-1 кластера; nil, если ни один не прошёл фильтр.
    var topLeakTitle: String?
    var advisorComputedAt: Date
}
