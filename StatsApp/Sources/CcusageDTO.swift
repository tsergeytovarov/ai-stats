import Foundation

/// ccusage отдаёт разные схемы для разных провайдеров. Парсер
/// выбирает нужную DTO по `source`.

// MARK: - Claude

struct CcusageClaudeReport: Decodable {
    let daily: [CcusageClaudeDay]
}

struct CcusageClaudeDay: Decodable {
    let date: String
    let modelsUsed: [String]
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheCreationTokens: Int64
    let cacheReadTokens: Int64
    let modelBreakdowns: [ClaudeModelBreakdown]?
    /// Day-level стоимость от ccusage. Опционально — старые версии ccusage могли
    /// не отдавать. Если nil, парсер фолбэчит на сумму per-model cost.
    let totalCost: Double?
}

struct ClaudeModelBreakdown: Decodable {
    let modelName: String
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheCreationTokens: Int64
    let cacheReadTokens: Int64
    /// Per-model стоимость от ccusage. Опционально — fallback см. CcusageParser.
    let cost: Double?
}

// MARK: - Codex

struct CcusageCodexReport: Decodable {
    let daily: [CcusageCodexDay]
}

struct CcusageCodexDay: Decodable {
    let date: String
    let inputTokens: Int64
    let outputTokens: Int64
    // ccusage сменил codex-схему: было `cachedInputTokens`, стало `cacheReadTokens` +
    // `cacheCreationTokens` (как у claude). Опциональные — чтобы декод не падал, если
    // поле снова переименуют/уберут (раньше required-поле роняло весь синк codex'а).
    let cacheReadTokens: Int64?
    let cacheCreationTokens: Int64?
    let models: [String: CodexModelStats]?
    /// Day-level стоимость от ccusage (поле "costUSD"). Опционально — fallback на
    /// PricingTable-сумму по моделям, см. CcusageParser.
    let costUSD: Double?

    var modelNames: [String] { models?.keys.sorted() ?? [] }
}

struct CodexModelStats: Decodable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheReadTokens: Int64?
    let cacheCreationTokens: Int64?
    let reasoningOutputTokens: Int64?
}
