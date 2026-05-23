import Foundation
import GRDB

/// Тянет суммы tokens (input+output без кэша) из локальной БД и шлёт на aiuse-api.
///
/// **Daily-aligned bucket'ы:** локальная БД хранит daily агрегаты (ai_usage UNIQUE day,source),
/// `ccusage` не отдаёт hourly. Шлём один snapshot/день с hour_bucket = midnight UTC.
/// Серверная схема (hourly) совместима, SUM по day/week/month работает.
@MainActor
final class SnapshotSyncer {
    private let db: any DatabaseWriter
    private let api: AiuseAPIClient
    private let now: () -> Date
    private let lookbackDays: Int

    init(db: any DatabaseWriter,
         api: AiuseAPIClient,
         lookbackDays: Int = 7,
         now: @escaping () -> Date = Date.init) {
        self.db = db
        self.api = api
        self.lookbackDays = lookbackDays
        self.now = now
    }

    /// Один тик: обновить pending_snapshots из локальной БД и отправить на сервер.
    /// Возвращает количество принятых сервером snapshot'ов. 0 — если профиль не создан
    /// или шаринг выключен (это не ошибка).
    @discardableResult
    func runOnce() async throws -> Int {
        // 1. Профиль есть и шаринг включен?
        let profile = try await db.read { db in
            try StatsQueries.loadMyProfile(db)
        }
        guard let profile, profile.sharingEnabled else {
            return 0
        }

        // 2. Обновляем pending_snapshots из ai_usage за последние lookbackDays.
        let sinceDay = Self.isoDayString(date: now().addingTimeInterval(-Double(lookbackDays) * 86400))
        try await db.write { db in
            try StatsQueries.refreshPendingSnapshots(in: db, sinceDay: sinceDay)
        }

        // 3. Загружаем pending → шлём батчем.
        let pending = try await db.read { db in
            try StatsQueries.loadReadyPendingSnapshots(db)
        }
        guard !pending.isEmpty else { return 0 }

        let items = pending.map { row in
            SnapshotItem(
                hourBucket: Self.iso8601String(fromUnixSeconds: row.hourBucket),
                tokensInput: row.tokensInput,
                tokensOutput: row.tokensOutput
            )
        }

        do {
            let result = try await api.sendSnapshots(items)
            let buckets = pending.map { $0.hourBucket }
            try await db.write { db in
                try StatsQueries.deletePendingSnapshots(db, hourBuckets: buckets)
            }
            return result.accepted
        } catch {
            let buckets = pending.map { $0.hourBucket }
            let message = "\(error)"
            try await db.write { db in
                try StatsQueries.incrementPendingAttempts(db, hourBuckets: buckets, lastError: message)
            }
            throw error
        }
    }

    /// Date → "YYYY-MM-DD" UTC.
    static func isoDayString(date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// unix seconds → "2026-05-23T00:00:00Z".
    static func iso8601String(fromUnixSeconds seconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
