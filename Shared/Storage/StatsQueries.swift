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

struct ModelTotal: Equatable, Hashable {
    let model: String
    let source: String
    let costUsd: Double
    let inputTokens: Int64
    let outputTokens: Int64
}

enum StatsQueries {
    static func aiTotals(in db: GRDB.Database, days: [String]) throws -> AITotals {
        guard !days.isEmpty else { return AITotals(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0) }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT COALESCE(SUM(cost_usd), 0) AS c,
                   COALESCE(SUM(input_tokens_no_cache), 0) AS i,
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
                   SUM(input_tokens_no_cache) AS i,
                   SUM(output_tokens) AS o
            FROM ai_usage WHERE day IN (\(placeholders))
            GROUP BY source ORDER BY source
        """
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(days)).map {
            SourceTotal(source: $0["source"], costUsd: $0["c"], inputTokens: $0["i"], outputTokens: $0["o"])
        }
    }

    /// Топ-N моделей по суммарному cost_usd за переданные дни.
    static func topModels(in db: GRDB.Database, days: [String], limit: Int = 5) throws -> [ModelTotal] {
        guard !days.isEmpty else { return [] }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT model, source, SUM(cost_usd) AS c, SUM(input_tokens_no_cache) AS i, SUM(output_tokens) AS o
            FROM ai_usage_model WHERE day IN (\(placeholders))
            GROUP BY model, source
            ORDER BY c DESC
            LIMIT ?
        """
        var args = StatementArguments(days)
        args += StatementArguments([limit])
        return try Row.fetchAll(db, sql: sql, arguments: args).map {
            ModelTotal(model: $0["model"], source: $0["source"], costUsd: $0["c"], inputTokens: $0["i"], outputTokens: $0["o"])
        }
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

    // MARK: - aiuse: my_profile

    static func loadMyProfile(_ db: GRDB.Database) throws -> MyProfileRow? {
        try MyProfileRow.fetchOne(db, key: 1)
    }

    static func saveMyProfile(_ db: GRDB.Database, _ profile: MyProfileRow) throws {
        try profile.save(db)
    }

    static func deleteMyProfile(_ db: GRDB.Database) throws {
        _ = try MyProfileRow.deleteOne(db, key: 1)
    }

    /// Точечный апдейт своего аватара. Если профиля нет — no-op.
    /// blob=nil очищает локальный кэш (например, при удалении аватарки на сервере).
    static func updateMyAvatar(
        _ db: GRDB.Database, blob: Data?, mime: String?, etag: String?
    ) throws {
        guard var row = try MyProfileRow.fetchOne(db, key: 1) else { return }
        row.avatarBlob = blob
        row.avatarMime = mime
        row.avatarEtag = etag
        try row.update(db)
    }

}
