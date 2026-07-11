import Foundation
import GRDB

/// Upsert аналитики — политика `INSERT OR REPLACE` по UNIQUE-ключу (не never-decrease):
/// ход, заингещённый усечённым во время живой сессии, дополняется при следующем тике.
enum AnalyticsUpserter {
    /// Ход: replace по UNIQUE(source, session, ts). id обнуляем — назначится AUTOINCREMENT.
    static func upsertTurn(_ row: AnalyticsTurnRow, in db: GRDB.Database) throws {
        var r = row
        r.id = nil
        try r.insert(db, onConflict: .replace)
    }

    /// Наблюдение лимита: replace по UNIQUE(path, ts, window).
    static func upsertRateLimit(_ row: AnalyticsRateLimitRow, in db: GRDB.Database) throws {
        try row.insert(db, onConflict: .replace)
    }
}
