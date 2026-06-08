import Foundation
import os.log

/// Цены в USD за 1M токенов. Источник — публичные прайсы Anthropic / OpenAI.
/// Anthropic-ставки сверены с https://platform.claude.com/docs/en/about-claude/pricing (2026-06-08),
/// OpenAI — с https://developers.openai.com/api/docs/pricing.
/// cache-create считается раздельно: 5-минутный write (1.25 × input) и 1-часовой (2 × input).
/// Когда модель не распознана даже по семейству, используем нулевые ставки и логируем через AppLogger.pricing.
struct ModelRate: Equatable {
    let inputPerM: Double
    let outputPerM: Double
    let cacheReadPerM: Double
    let cacheCreatePerM: Double      // 5-минутный cache-write (1.25 × input)
    let cacheCreate1hPerM: Double    // 1-часовой cache-write (2 × input)
}

enum PricingTable {
    // Ставки семейств Claude 4.x (Opus 4.5+, Sonnet 4.5+, Haiku 4.5 — единый прайс внутри семейства).
    // Один источник правды: используются и в таблице точных совпадений, и в family-fallback ниже,
    // чтобы ставки не разъезжались при добавлении новой модели.
    static let opusRate   = ModelRate(inputPerM: 5.00, outputPerM: 25.00, cacheReadPerM: 0.50, cacheCreatePerM: 6.25, cacheCreate1hPerM: 10.00)
    static let sonnetRate = ModelRate(inputPerM: 3.00, outputPerM: 15.00, cacheReadPerM: 0.30, cacheCreatePerM: 3.75, cacheCreate1hPerM: 6.00)
    static let haikuRate  = ModelRate(inputPerM: 1.00, outputPerM: 5.00,  cacheReadPerM: 0.10, cacheCreatePerM: 1.25, cacheCreate1hPerM: 2.00)

    /// Точное совпадение по имени модели → ставка.
    static let rates: [String: ModelRate] = [
        // Anthropic — Claude 4.x family
        "claude-opus-4-8":           opusRate,
        "claude-opus-4-7":           opusRate,
        "claude-opus-4-5":           opusRate,
        "claude-sonnet-4-6":         sonnetRate,
        "claude-sonnet-4-5":         sonnetRate,
        "claude-haiku-4-5-20251001": haikuRate,
        "claude-haiku-4-5":          haikuRate,

        // OpenAI — gpt-5.x family (cache-write у OpenAI не тарифицируется отдельно → 0)
        "gpt-5.5":                   ModelRate(inputPerM: 5.00, outputPerM: 30.00, cacheReadPerM: 0.50,  cacheCreatePerM: 0.00, cacheCreate1hPerM: 0.00),
        "gpt-5.4":                   ModelRate(inputPerM: 2.50, outputPerM: 15.00, cacheReadPerM: 0.25,  cacheCreatePerM: 0.00, cacheCreate1hPerM: 0.00),
        "gpt-5.4-mini":              ModelRate(inputPerM: 0.75, outputPerM: 4.50,  cacheReadPerM: 0.075, cacheCreatePerM: 0.00, cacheCreate1hPerM: 0.00),
        // codex-auto-review — внутренний лейбл фичи Codex, не публичный SKU; ставка не верифицирована.
        "codex-auto-review":         ModelRate(inputPerM: 5.00, outputPerM: 15.00, cacheReadPerM: 0.63,  cacheCreatePerM: 0.00, cacheCreate1hPerM: 0.00),
    ]

    private static let unknown = ModelRate(inputPerM: 0, outputPerM: 0, cacheReadPerM: 0, cacheCreatePerM: 0, cacheCreate1hPerM: 0)

    /// Возвращает ставку: точное совпадение → семейный fallback по префиксу → нулевая ставка с warning.
    static func rate(for model: String) -> ModelRate {
        if let r = rates[model] { return r }
        // Узнаваемая Claude-модель, которой ещё нет в таблице (например, вышла после последнего
        // обновления прайса) — берём текущую ставку семейства вместо молчаливого нуля. Так новый
        // claude-opus-4-9 не обнулит статистику. Логируем, чтобы не забыть обновить таблицу.
        if let (family, r) = familyRate(for: model) {
            AppLogger.pricing.warning("Unknown model '\(model, privacy: .public)', falling back to \(family, privacy: .public) family rate")
            return r
        }
        // Model name = public identifier (publicly известный SKU из API ответа).
        AppLogger.pricing.warning("Unknown model '\(model, privacy: .public)', using zero rate")
        return unknown
    }

    /// Ставка по семейству для незнакомой, но узнаваемой Claude-модели.
    private static func familyRate(for model: String) -> (family: String, rate: ModelRate)? {
        if model.hasPrefix("claude-opus-")   { return ("opus", opusRate) }
        if model.hasPrefix("claude-sonnet-") { return ("sonnet", sonnetRate) }
        if model.hasPrefix("claude-haiku-")  { return ("haiku", haikuRate) }
        return nil
    }

    /// Считает стоимость в USD по разбивке по токенам.
    /// `cacheCreateTokens` — все cache-write токены (вкл. 1h). Из них `cacheCreate1hTokens`
    /// записаны с 1-часовым TTL (дороже); остальное тарифицируется по 5-минутной ставке.
    /// ccusage не отдаёт разбивку 1h/5m → передаёт только `cacheCreateTokens` (всё как 5m).
    static func cost(model: String,
                     inputTokens: Int64,
                     outputTokens: Int64,
                     cacheReadTokens: Int64,
                     cacheCreateTokens: Int64,
                     cacheCreate1hTokens: Int64 = 0) -> Double {
        let r = rate(for: model)
        let perM = 1_000_000.0
        let cacheCreate1h = min(cacheCreate1hTokens, cacheCreateTokens)
        let cacheCreate5m = cacheCreateTokens - cacheCreate1h
        return Double(inputTokens)       / perM * r.inputPerM
             + Double(outputTokens)      / perM * r.outputPerM
             + Double(cacheReadTokens)   / perM * r.cacheReadPerM
             + Double(cacheCreate5m)     / perM * r.cacheCreatePerM
             + Double(cacheCreate1h)     / perM * r.cacheCreate1hPerM
    }
}
