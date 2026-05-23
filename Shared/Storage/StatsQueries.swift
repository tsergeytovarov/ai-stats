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

struct GitHubLOC: Equatable {
    let additions: Int64
    let deletions: Int64
}

struct ModelTotal: Equatable, Hashable {
    let model: String
    let source: String
    let costUsd: Double
    let inputTokens: Int64
    let outputTokens: Int64
}

struct RepoTotal: Equatable, Hashable {
    let repo: String
    let commits: Int64
    let additions: Int64
    let deletions: Int64
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

    /// Суммирует LOC по дням напрямую из github_loc_daily.
    static func githubLOC(in db: GRDB.Database, days: [String]) throws -> GitHubLOC {
        guard !days.isEmpty else { return GitHubLOC(additions: 0, deletions: 0) }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT COALESCE(SUM(additions), 0) AS a, COALESCE(SUM(deletions), 0) AS d
            FROM github_loc_daily WHERE day IN (\(placeholders))
        """
        let row = try Row.fetchOne(db, sql: sql, arguments: StatementArguments(days))!
        return GitHubLOC(additions: row["a"], deletions: row["d"])
    }

    /// Топ-N моделей по суммарному cost_usd за переданные дни.
    static func topModels(in db: GRDB.Database, days: [String], limit: Int = 5) throws -> [ModelTotal] {
        guard !days.isEmpty else { return [] }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT model, source, SUM(cost_usd) AS c, SUM(input_tokens) AS i, SUM(output_tokens) AS o
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

    /// Топ-N репозиториев по коммитам за переданные дни, с приджойненным LOC.
    static func topRepos(in db: GRDB.Database, days: [String], limit: Int = 5) throws -> [RepoTotal] {
        guard !days.isEmpty else { return [] }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT ga.repo AS repo,
                   SUM(ga.commits) AS commits,
                   COALESCE(loc.adds, 0) AS adds,
                   COALESCE(loc.dels, 0) AS dels
            FROM github_activity ga
            LEFT JOIN (
                SELECT repo, SUM(additions) AS adds, SUM(deletions) AS dels
                FROM github_loc_daily
                WHERE day IN (\(placeholders))
                GROUP BY repo
            ) loc ON loc.repo = ga.repo
            WHERE ga.day IN (\(placeholders)) AND ga.commits > 0
            GROUP BY ga.repo
            ORDER BY commits DESC
            LIMIT ?
        """
        var args = StatementArguments(days)
        args += StatementArguments(days)
        args += StatementArguments([limit])
        return try Row.fetchAll(db, sql: sql, arguments: args).map {
            RepoTotal(repo: $0["repo"], commits: $0["commits"], additions: $0["adds"], deletions: $0["dels"])
        }
    }

    /// Возвращает массив additions параллельно `days`. Если за день нет данных — 0.
    static func dailyAdditionsSeries(in db: GRDB.Database, days: [String]) throws -> [Double] {
        guard !days.isEmpty else { return [] }
        let placeholders = days.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT day, SUM(additions) AS a
            FROM github_loc_daily WHERE day IN (\(placeholders))
            GROUP BY day
        """
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(days))
        var map: [String: Double] = [:]
        for row in rows { map[row["day"]] = Double(row["a"] as Int64) }
        return days.map { map[$0] ?? 0.0 }
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

    // MARK: - aiuse: pending_snapshots

    /// Daily aggregates из ai_usage за период → upsert в pending_snapshots.
    /// hour_bucket = unix seconds полночи UTC соответствующего дня.
    /// SUM по всем providers (claude+codex и т.д.) — лидерборду интересен суммарный объём.
    static func refreshPendingSnapshots(in db: GRDB.Database, sinceDay: String) throws {
        // Берём input_tokens_no_cache (без cache reads/writes) — это то что
        // спек называет "input без кэша". output_tokens у нас итак без кэша.
        let rows = try Row.fetchAll(db, sql: """
            SELECT day,
                   COALESCE(SUM(input_tokens_no_cache), 0) AS sum_input,
                   COALESCE(SUM(output_tokens), 0) AS sum_output
            FROM ai_usage
            WHERE day >= ?
            GROUP BY day
            """, arguments: [sinceDay])

        for row in rows {
            let day: String = row["day"]
            let input: Int64 = row["sum_input"]
            let output: Int64 = row["sum_output"]
            guard let bucket = midnightUTCUnixTimestamp(fromIsoDay: day) else { continue }
            // Upsert: если запись существует — обновляем counts, если нет — создаём.
            if var existing = try PendingSnapshotRow.fetchOne(db, key: bucket) {
                existing.tokensInput = input
                existing.tokensOutput = output
                // attempts/last_error не сбрасываем — retry поведение сохраняется.
                try existing.update(db)
            } else {
                let row = PendingSnapshotRow(
                    hourBucket: bucket,
                    tokensInput: input,
                    tokensOutput: output,
                    attempts: 0,
                    lastError: nil
                )
                try row.insert(db)
            }
        }
    }

    static func loadReadyPendingSnapshots(_ db: GRDB.Database,
                                          maxAttempts: Int = 5,
                                          limit: Int = 168) throws -> [PendingSnapshotRow] {
        try PendingSnapshotRow
            .filter(PendingSnapshotRow.Columns.attempts < maxAttempts)
            .order(PendingSnapshotRow.Columns.hourBucket.desc)
            .limit(limit)
            .fetchAll(db)
    }

    static func deletePendingSnapshots(_ db: GRDB.Database, hourBuckets: [Int64]) throws {
        guard !hourBuckets.isEmpty else { return }
        _ = try PendingSnapshotRow
            .filter(hourBuckets.contains(PendingSnapshotRow.Columns.hourBucket))
            .deleteAll(db)
    }

    static func incrementPendingAttempts(_ db: GRDB.Database,
                                         hourBuckets: [Int64],
                                         lastError: String) throws {
        guard !hourBuckets.isEmpty else { return }
        for bucket in hourBuckets {
            guard var row = try PendingSnapshotRow.fetchOne(db, key: bucket) else { continue }
            row.attempts += 1
            row.lastError = lastError
            try row.update(db)
        }
    }

    // MARK: - aiuse: friend_profiles

    static func upsertFriendProfile(_ db: GRDB.Database, _ row: FriendProfileRow) throws {
        try row.save(db)
    }

    static func loadFriendProfiles(_ db: GRDB.Database) throws -> [FriendProfileRow] {
        try FriendProfileRow.order(FriendProfileRow.Columns.displayName).fetchAll(db)
    }

    static func loadFriendProfile(_ db: GRDB.Database, friendCode: String) throws -> FriendProfileRow? {
        try FriendProfileRow.fetchOne(db, key: friendCode)
    }

    static func deleteFriendProfilesNotIn(_ db: GRDB.Database, friendCodes: [String]) throws {
        if friendCodes.isEmpty {
            _ = try FriendProfileRow.deleteAll(db)
        } else {
            _ = try FriendProfileRow
                .filter(!friendCodes.contains(FriendProfileRow.Columns.friendCode))
                .deleteAll(db)
        }
    }

    static func updateFriendAvatar(
        _ db: GRDB.Database, friendCode: String, blob: Data?, mime: String?, etag: String?
    ) throws {
        guard var row = try FriendProfileRow.fetchOne(db, key: friendCode) else { return }
        row.avatarBlob = blob
        row.avatarMime = mime
        row.avatarEtag = etag
        try row.update(db)
    }

    // MARK: - aiuse: leaderboard_cache

    static func saveLeaderboardCache(_ db: GRDB.Database, period: String, payloadJson: String) throws {
        let row = LeaderboardCacheRow(
            period: period,
            fetchedAt: Date().timeIntervalSince1970,
            payloadJson: payloadJson
        )
        try row.save(db)
    }

    static func loadLeaderboardCache(_ db: GRDB.Database, period: String) throws -> LeaderboardCacheRow? {
        try LeaderboardCacheRow.fetchOne(db, key: period)
    }

    /// "2026-05-23" → unix seconds полночи UTC.
    static func midnightUTCUnixTimestamp(fromIsoDay day: String) -> Int64? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.timeZone = TimeZone(identifier: "UTC")
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        return Int64(date.timeIntervalSince1970)
    }
}
