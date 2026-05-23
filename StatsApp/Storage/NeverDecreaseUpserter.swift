import Foundation
import GRDB

enum NeverDecreaseUpserter {
    /// Вставляет или апдейтит строку AIUsage по политике «не уменьшаем cost_usd».
    /// Сравнение по `cost_usd` — это наша главная метрика. Tokens обновляются вместе с cost (always-in-sync).
    static func upsertAIUsage(_ row: AIUsageRow, in db: GRDB.Database) throws {
        if let existing = try AIUsageRow
            .filter(AIUsageRow.Columns.day == row.day && AIUsageRow.Columns.source == row.source)
            .fetchOne(db) {
            // never-decrease по cost_usd + один backfill-pass для input_tokens_no_cache
            // (миграция v6 добавила колонку с 0; первый sync после обновления
            // обнаруживает existing.inputTokensNoCache == 0 и обновляет даже при равном cost).
            let needsBackfill = existing.inputTokensNoCache == 0 && row.inputTokensNoCache > 0
            guard row.costUsd > existing.costUsd || needsBackfill else { return }
            var updated = row
            updated.id = existing.id
            try updated.update(db)
        } else {
            var inserted = row
            inserted.id = nil
            try inserted.insert(db)
        }
    }

    /// То же для per-model breakdown: метрика сравнения — cost_usd + backfill.
    static func upsertAIUsageModel(_ row: AIUsageModelRow, in db: GRDB.Database) throws {
        if let existing = try AIUsageModelRow
            .filter(AIUsageModelRow.Columns.day == row.day
                 && AIUsageModelRow.Columns.source == row.source
                 && AIUsageModelRow.Columns.model == row.model)
            .fetchOne(db) {
            let needsBackfill = existing.inputTokensNoCache == 0 && row.inputTokensNoCache > 0
            guard row.costUsd > existing.costUsd || needsBackfill else { return }
            var updated = row
            updated.id = existing.id
            try updated.update(db)
        } else {
            var inserted = row
            inserted.id = nil
            try inserted.insert(db)
        }
    }

    /// То же для LOC: метрика сравнения — additions + deletions (общий объём).
    static func upsertGitHubLOCDaily(_ row: GitHubLOCDailyRow, in db: GRDB.Database) throws {
        let newTotal = row.additions + row.deletions
        if let existing = try GitHubLOCDailyRow
            .filter(GitHubLOCDailyRow.Columns.day == row.day && GitHubLOCDailyRow.Columns.repo == row.repo)
            .fetchOne(db) {
            let oldTotal = existing.additions + existing.deletions
            guard newTotal > oldTotal else { return }
            var updated = row
            updated.id = existing.id
            try updated.update(db)
        } else {
            var inserted = row
            inserted.id = nil
            try inserted.insert(db)
        }
    }

    /// То же для GitHub: метрика сравнения — commits.
    static func upsertGitHub(_ row: GitHubRow, in db: GRDB.Database) throws {
        if let existing = try GitHubRow
            .filter(GitHubRow.Columns.day == row.day && GitHubRow.Columns.repo == row.repo)
            .fetchOne(db) {
            guard row.commits > existing.commits else { return }
            var updated = row
            updated.id = existing.id
            try updated.update(db)
        } else {
            var inserted = row
            inserted.id = nil
            try inserted.insert(db)
        }
    }
}
