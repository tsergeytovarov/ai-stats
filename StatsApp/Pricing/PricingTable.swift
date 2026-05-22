import Foundation

/// Цены в USD за 1M токенов. Источник — публичные прайсы Anthropic / OpenAI на май 2026.
/// Когда модель отсутствует в таблице, используем нулевые ставки и логируем NSLog.
struct ModelRate: Equatable {
    let inputPerM: Double
    let outputPerM: Double
    let cacheReadPerM: Double
    let cacheCreatePerM: Double
}

enum PricingTable {
    /// Точное совпадение по имени модели → ставка.
    static let rates: [String: ModelRate] = [
        // Anthropic — claude 4.x family
        "claude-opus-4-7":           ModelRate(inputPerM: 15.00, outputPerM: 75.00, cacheReadPerM: 1.50,  cacheCreatePerM: 18.75),
        "claude-opus-4-5":           ModelRate(inputPerM: 15.00, outputPerM: 75.00, cacheReadPerM: 1.50,  cacheCreatePerM: 18.75),
        "claude-sonnet-4-6":         ModelRate(inputPerM: 3.00,  outputPerM: 15.00, cacheReadPerM: 0.30,  cacheCreatePerM: 3.75),
        "claude-sonnet-4-5":         ModelRate(inputPerM: 3.00,  outputPerM: 15.00, cacheReadPerM: 0.30,  cacheCreatePerM: 3.75),
        "claude-haiku-4-5-20251001": ModelRate(inputPerM: 0.80,  outputPerM: 4.00,  cacheReadPerM: 0.08,  cacheCreatePerM: 1.00),
        "claude-haiku-4-5":          ModelRate(inputPerM: 0.80,  outputPerM: 4.00,  cacheReadPerM: 0.08,  cacheCreatePerM: 1.00),

        // OpenAI — gpt-5.x family (ставки приближённые на май 2026)
        "gpt-5.5":                   ModelRate(inputPerM: 10.00, outputPerM: 30.00, cacheReadPerM: 1.25,  cacheCreatePerM: 0.00),
        "gpt-5.4":                   ModelRate(inputPerM: 1.25,  outputPerM: 10.00, cacheReadPerM: 0.13,  cacheCreatePerM: 0.00),
        "gpt-5.4-mini":              ModelRate(inputPerM: 0.25,  outputPerM: 2.00,  cacheReadPerM: 0.03,  cacheCreatePerM: 0.00),
        "codex-auto-review":         ModelRate(inputPerM: 5.00,  outputPerM: 15.00, cacheReadPerM: 0.63,  cacheCreatePerM: 0.00),
    ]

    private static let unknown = ModelRate(inputPerM: 0, outputPerM: 0, cacheReadPerM: 0, cacheCreatePerM: 0)

    /// Возвращает ставку. Если модели нет — нулевая ставка плюс NSLog.
    static func rate(for model: String) -> ModelRate {
        if let r = rates[model] { return r }
        NSLog("ai-stats pricing: unknown model '\(model)', using zero rate")
        return unknown
    }

    /// Считает стоимость в USD по разбивке по токенам.
    static func cost(model: String,
                     inputTokens: Int64,
                     outputTokens: Int64,
                     cacheReadTokens: Int64,
                     cacheCreateTokens: Int64) -> Double {
        let r = rate(for: model)
        let perM = 1_000_000.0
        return Double(inputTokens)       / perM * r.inputPerM
             + Double(outputTokens)      / perM * r.outputPerM
             + Double(cacheReadTokens)   / perM * r.cacheReadPerM
             + Double(cacheCreateTokens) / perM * r.cacheCreatePerM
    }
}
