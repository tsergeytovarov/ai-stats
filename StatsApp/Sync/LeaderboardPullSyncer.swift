import Foundation
import GRDB
import os.log

/// Тянет /api/leaderboard для всех 4 периодов и кэширует JSON-ом локально.
/// UI-компоненты могут читать кэш для оффлайн-фолбэка.
@MainActor
final class LeaderboardPullSyncer {
    static let periods: [String] = ["day", "week", "month", "24h"]

    private let db: any DatabaseWriter
    private let api: AiuseAPIClient
    private let hasAccount: () -> Bool

    init(db: any DatabaseWriter, api: AiuseAPIClient, hasAccount: @escaping () -> Bool) {
        self.db = db
        self.api = api
        self.hasAccount = hasAccount
    }

    @discardableResult
    func runOnce() async throws -> Int {
        guard hasAccount() else { return 0 }

        var saved = 0
        for period in Self.periods {
            do {
                let resp = try await api.getLeaderboard(period: period)
                let data = try JSONEncoder().encode(resp)
                guard let json = String(data: data, encoding: .utf8) else { continue }
                try await db.write { db in
                    try StatsQueries.saveLeaderboardCache(db, period: period, payloadJson: json)
                }
                saved += 1
            } catch AiuseAPIError.http(403, _) {
                // sharing_enabled = false — нормальный кейс, не падаем.
                return saved
            } catch {
                // period — публичный identifier ("day"/"week"/...). error может содержать server body.
                AppLogger.aiuse.error(
                    "Leaderboard pull failed [\(period, privacy: .public)]: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        return saved
    }
}
