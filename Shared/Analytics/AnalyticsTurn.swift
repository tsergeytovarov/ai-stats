import Foundation

/// Разобранный «ход» агента — сырые поля из транскрипта, до расчёта стоимости/ступени.
/// Соответствует колонкам `analytics_turns` без id и без вычисляемых
/// cost_usd/heur_tier/cf_model/cf_usd/exp_saved_usd (их проставляет `TurnCostCalculator.enrich`).
/// `day` вычисляется на этапе enrich из `ts` в локальной таймзоне.
struct ParsedTurn: Equatable {
    var source: String
    var ts: String = ""
    var session: String = ""
    var project: String = ""
    var model: String = ""
    var effort: String = ""
    var promptHead: String = ""
    var promptChars: Int64 = 0
    var nRequests: Int64 = 0
    var nToolCalls: Int64 = 0
    var nEdits: Int64 = 0
    var inputTokens: Int64 = 0
    var cacheRead: Int64 = 0
    var cacheCreate5m: Int64 = 0
    var cacheCreate1h: Int64 = 0
    var outputTokens: Int64 = 0

    /// Правило `origin` (спека 5.2, порт `origin_of`): после снятия ведущих пробелов
    /// `<command-` → human (слэш-команда — инициатива пользователя); любой другой
    /// ведущий `<` → auto (task-notification, системная обвязка); иначе → human.
    var origin: String {
        let h = promptHead.drop(while: { $0.isWhitespace })
        if h.hasPrefix("<command-") { return "human" }
        if h.hasPrefix("<") { return "auto" }
        return "human"
    }
}

/// Наблюдение лимита Codex из `rate_limits` события `token_count`. `path` добавляет
/// ингестор при записи в `analytics_rate_limits`.
struct ParsedRateLimit: Equatable {
    var ts: String
    var window: String       // "primary" (5h) | "secondary" (week)
    var usedPercent: Double
}
