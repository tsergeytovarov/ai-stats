import Foundation
import GRDB

/// Тянет суммы tokens (input+output без кэша) из локальной БД и шлёт на aiuse-api.
///
/// **Daily-aligned bucket'ы:** локальная БД хранит daily агрегаты (ai_usage UNIQUE day,source),
/// `ccusage` не отдаёт hourly. Шлём один snapshot/день с hour_bucket = midnight UTC.
/// Серверная схема (hourly) совместима, SUM по day/week/month работает.
///
/// **Два режима окна:**
/// - обычный тик — последние `lookbackDays` (по умолчанию 7): дешёвый инкремент.
/// - `backfill: true` — вся накопленная история (`backfillLookbackDays`): вызывается
///   один раз при включении шаринга/входе, чтобы залить то, что накопилось ДО шаринга.
///   Без этого юзер, включивший шаринг не в первый день, светил бы на лидерборде 0.
@MainActor
final class SnapshotSyncer {
    private let db: any DatabaseWriter
    private let api: AiuseAPIClient
    private let now: () -> Date
    private let lookbackDays: Int
    private let backfillLookbackDays: Int
    /// Лимит снапшотов в одном POST — совпадает с серверным (168 = неделя hourly).
    private let batchLimit = 168

    init(db: any DatabaseWriter,
         api: AiuseAPIClient,
         lookbackDays: Int = 7,
         backfillLookbackDays: Int = 3650,
         now: @escaping () -> Date = Date.init) {
        self.db = db
        self.api = api
        self.lookbackDays = lookbackDays
        self.backfillLookbackDays = backfillLookbackDays
        self.now = now
    }

    /// Один тик: обновить pending_snapshots из локальной БД и отправить на сервер.
    /// Возвращает суммарное количество принятых сервером snapshot'ов.
    ///
    /// `backfill` — залить всю историю, а не только последние `lookbackDays`.
    @discardableResult
    func runOnce(backfill: Bool = false) async throws -> Int {
        // 1. Профиль есть и шаринг включён?
        let profile = try await db.read { db in
            try StatsQueries.loadMyProfile(db)
        }
        guard let profile else {
            AppLogger.aiuse.info("snapshot sync: профиля нет — пропуск")
            return 0
        }
        guard profile.sharingEnabled else {
            AppLogger.aiuse.info("snapshot sync: шаринг выключен локально — пропуск (на сервере мог остаться включённым)")
            return 0
        }

        // 2. Обновляем pending_snapshots из ai_usage за нужное окно.
        let lookback = backfill ? backfillLookbackDays : lookbackDays
        let sinceDay = Self.isoDayString(date: now().addingTimeInterval(-Double(lookback) * 86400))
        try await db.write { db in
            try StatsQueries.refreshPendingSnapshots(in: db, sinceDay: sinceDay)
        }

        // 3. Шлём пачками по batchLimit, пока есть готовые pending.
        //    Без пагинации backfill истории (>168 дней) застрял бы: уходил бы
        //    только верхний батч, остальное копилось бы.
        var totalAccepted = 0
        while true {
            let pending = try await db.read { db in
                try StatsQueries.loadReadyPendingSnapshots(db, limit: self.batchLimit)
            }
            guard !pending.isEmpty else { break }

            let items = pending.map { row in
                SnapshotItem(
                    hourBucket: Self.iso8601String(fromUnixSeconds: row.hourBucket),
                    tokensInput: row.tokensInput,
                    tokensOutput: row.tokensOutput
                )
            }
            let buckets = pending.map { $0.hourBucket }

            do {
                let result = try await api.sendSnapshots(items)
                try await db.write { db in
                    try StatsQueries.deletePendingSnapshots(db, hourBuckets: buckets)
                }
                totalAccepted += result.accepted
            } catch {
                try await db.write { db in
                    try StatsQueries.incrementPendingAttempts(db, hourBuckets: buckets, lastError: "\(error)")
                }
                AppLogger.aiuse.error("snapshot sync: отправка \(items.count, privacy: .public) шт. упала — \(error.localizedDescription, privacy: .private)")
                throw error
            }
        }

        AppLogger.aiuse.info("snapshot sync: отправлено \(totalAccepted, privacy: .public) snapshot'ов\(backfill ? " (backfill всей истории)" : "")")
        return totalAccepted
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
