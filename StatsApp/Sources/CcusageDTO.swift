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
    let totalCost: Double
}

// MARK: - Codex

struct CcusageCodexReport: Decodable {
    let daily: [CcusageCodexDay]
}

struct CcusageCodexDay: Decodable {
    let date: String
    let inputTokens: Int64
    let outputTokens: Int64
    let cachedInputTokens: Int64
    let costUSD: Double
    let models: [String: CodexModelStats]?

    var modelNames: [String] {
        models?.keys.sorted() ?? []
    }
}

struct CodexModelStats: Decodable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cachedInputTokens: Int64?
}
