import Foundation
import GRDB

/// История лимитов и статусы опроса. Снапшот пишется только при изменении —
/// история должна быть ступенчатой, иначе второй этап (прогноз по темпу) будет
/// считать темп по шуму опроса, а не по расходу.
final class LimitsRepository {
    private let db: any DatabaseWriter
    private let retentionDays: Int

    init(db: any DatabaseWriter, retentionDays: Int = 60) {
        self.db = db
        self.retentionDays = retentionDays
    }

    /// Записать результат опроса: окна — в историю, статус — в состояние.
    func record(_ limits: ProviderLimits, now: Date) async throws {
        let observedAt = Int64(now.timeIntervalSince1970)
        let provider = limits.provider.rawValue

        try await db.write { db in
            var lastSuccessAt = try LimitFetchStateRow
                .filter(LimitFetchStateRow.Columns.provider == provider)
                .fetchOne(db)?.lastSuccessAt

            for window in limits.windows {
                let resetsAt = window.resetsAt.map { Int64($0.timeIntervalSince1970) }
                let previous = try LimitSnapshotRow
                    .filter(LimitSnapshotRow.Columns.provider == provider)
                    .filter(LimitSnapshotRow.Columns.windowMinutes == window.windowMinutes)
                    .order(LimitSnapshotRow.Columns.observedAt.desc)
                    .fetchOne(db)
                if previous?.usedPercent == window.usedPercent, previous?.resetsAt == resetsAt {
                    continue
                }
                var row = LimitSnapshotRow(id: nil, provider: provider,
                                           windowMinutes: window.windowMinutes,
                                           usedPercent: window.usedPercent,
                                           resetsAt: resetsAt, observedAt: observedAt)
                try row.insert(db)
            }

            if !limits.windows.isEmpty {
                lastSuccessAt = observedAt
            }
            try LimitFetchStateRow(provider: provider,
                                   lastAttemptAt: observedAt,
                                   lastSuccessAt: lastSuccessAt,
                                   status: limits.status.rawValue,
                                   error: limits.error,
                                   retryAfterAt: nil)
                .insert(db, onConflict: .replace)
        }
    }

    /// Отдельно сохранить статус, не трогая историю (например, retry_after после 429).
    func saveState(provider: LimitProvider, status: LimitStatus, error: String?,
                   retryAfter: Date?, now: Date) async throws {
        let key = provider.rawValue
        let attemptAt = Int64(now.timeIntervalSince1970)
        try await db.write { db in
            let previous = try LimitFetchStateRow
                .filter(LimitFetchStateRow.Columns.provider == key)
                .fetchOne(db)
            try LimitFetchStateRow(provider: key,
                                   lastAttemptAt: attemptAt,
                                   lastSuccessAt: previous?.lastSuccessAt,
                                   status: status.rawValue,
                                   error: error,
                                   retryAfterAt: retryAfter.map { Int64($0.timeIntervalSince1970) })
                .insert(db, onConflict: .replace)
        }
    }

    /// Последнее известное состояние по каждому провайдеру: цифры из истории,
    /// статус — из состояния опроса.
    func latest() async throws -> [LimitProvider: ProviderLimits] {
        try await db.read { db in
            var result: [LimitProvider: ProviderLimits] = [:]
            for provider in LimitProvider.allCases {
                let key = provider.rawValue
                let state = try LimitFetchStateRow
                    .filter(LimitFetchStateRow.Columns.provider == key)
                    .fetchOne(db)
                let rows = try LimitSnapshotRow
                    .filter(LimitSnapshotRow.Columns.provider == key)
                    .order(LimitSnapshotRow.Columns.observedAt.desc)
                    .fetchAll(db)

                var seen = Set<Int>()
                var windows: [LimitWindow] = []
                for row in rows where !seen.contains(row.windowMinutes) {
                    seen.insert(row.windowMinutes)
                    windows.append(LimitWindow(
                        windowMinutes: row.windowMinutes,
                        usedPercent: row.usedPercent,
                        resetsAt: row.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }))
                }

                guard state != nil || !windows.isEmpty else { continue }
                result[provider] = ProviderLimits(
                    provider: provider,
                    windows: windows,
                    status: state.flatMap { LimitStatus(rawValue: $0.status) } ?? .stale,
                    fetchedAt: state?.lastSuccessAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    error: state?.error)
            }
            return result
        }
    }

    /// Убрать историю старше периода хранения — снапшоты копятся вечно иначе.
    func pruneOldSnapshots(now: Date) async throws {
        let cutoff = Int64(now.addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970)
        try await db.write { db in
            try db.execute(sql: "DELETE FROM limit_snapshots WHERE observed_at < ?",
                           arguments: [cutoff])
        }
    }
}
