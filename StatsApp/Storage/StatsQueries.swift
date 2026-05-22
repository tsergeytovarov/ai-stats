import Foundation
import GRDB

struct AITotals: Equatable {
    let totalCost: Double
    let totalInputTokens: Int64
    let totalOutputTokens: Int64
}

struct SourceTotal: Equatable {
    let source: String
    let costUsd: Double
    let inputTokens: Int64
    let outputTokens: Int64
}

struct GitHubTotals: Equatable {
    let totalCommits: Int64
    let uniqueRepos: Int
}

enum StatsQueries {
    static func aiTotals(in db: GRDB.Database, days: [String]) throws -> AITotals {
        guard !days.isEmpty else { return AITotals(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0) }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT COALESCE(SUM(cost_usd), 0) AS c,
                   COALESCE(SUM(input_tokens), 0) AS i,
                   COALESCE(SUM(output_tokens), 0) AS o
            FROM ai_usage WHERE day IN (\(placeholders))
        """
        let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(days))!
        return AITotals(
            totalCost: row["c"],
            totalInputTokens: row["i"],
            totalOutputTokens: row["o"]
        )
    }

    static func aiTotalsBySource(in db: GRDB.Database, days: [String]) throws -> [SourceTotal] {
        guard !days.isEmpty else { return [] }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT source,
                   SUM(cost_usd) AS c,
                   SUM(input_tokens) AS i,
                   SUM(output_tokens) AS o
            FROM ai_usage WHERE day IN (\(placeholders))
            GROUP BY source ORDER BY source
        """
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(days)).map {
            SourceTotal(source: $0["source"], costUsd: $0["c"], inputTokens: $0["i"], outputTokens: $0["o"])
        }
    }

    static func githubTotals(in db: GRDB.Database, days: [String]) throws -> GitHubTotals {
        guard !days.isEmpty else { return GitHubTotals(totalCommits: 0, uniqueRepos: 0) }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT COALESCE(SUM(commits), 0) AS c,
                   COUNT(DISTINCT repo) AS r
            FROM github_activity WHERE day IN (\(placeholders)) AND commits > 0
        """
        let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(days))!
        return GitHubTotals(totalCommits: row["c"], uniqueRepos: row["r"])
    }

    /// Возвращает массив cost_usd параллельно `days`. Если за день нет данных — 0.0.
    static func dailyAICostSeries(in db: GRDB.Database, days: [String]) throws -> [Double] {
        guard !days.isEmpty else { return [] }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT day, SUM(cost_usd) AS c
            FROM ai_usage WHERE day IN (\(placeholders))
            GROUP BY day
        """
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(days))
        var map: [String: Double] = [:]
        for row in rows { map[row["day"]] = row["c"] }
        return days.map { map[$0] ?? 0.0 }
    }
}
