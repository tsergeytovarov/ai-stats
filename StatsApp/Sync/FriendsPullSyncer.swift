import Foundation
import GRDB

/// Тянет список друзей с сервера и обновляет локальный кэш friend_profiles.
/// Параллельно догружает аватарки через ETag (только новые/изменённые).
@MainActor
final class FriendsPullSyncer {
    private let db: any DatabaseWriter
    private let api: AiuseAPIClient
    private let hasAccount: () -> Bool

    init(db: any DatabaseWriter, api: AiuseAPIClient, hasAccount: @escaping () -> Bool) {
        self.db = db
        self.api = api
        self.hasAccount = hasAccount
    }

    /// Один тик: GET /api/friends → upsert + удалить ушедших + догрузить аватарки.
    @discardableResult
    func runOnce() async throws -> Int {
        guard hasAccount() else { return 0 }

        let friends = try await api.listFriends()
        let now = Date().timeIntervalSince1970

        // Upsert новых, обновление существующих метаданных
        try await db.write { db in
            for f in friends {
                let existing = try FriendProfileRow.fetchOne(db, key: f.friendCode)
                var row = FriendProfileRow(
                    friendCode: f.friendCode,
                    displayName: f.displayName,
                    sharingEnabled: f.sharingEnabled,
                    avatarBlob: existing?.avatarBlob,
                    avatarMime: existing?.avatarMime,
                    avatarEtag: existing?.avatarEtag,
                    lastFetchedAt: now
                )
                try row.save(db)
            }
            // Удалить тех кого больше нет (рассинхрон с локальным кэшем)
            let serverCodes = friends.map { $0.friendCode }
            try StatsQueries.deleteFriendProfilesNotIn(db, friendCodes: serverCodes)
        }

        // Догрузка аватарок — последовательно, с ETag, тихо.
        // Ошибки не пробрасываем — это nice-to-have, не блокер.
        for f in friends {
            let existing = try? await db.read { try FriendProfileRow.fetchOne($0, key: f.friendCode) }
            await fetchAvatarIfNeeded(friendCode: f.friendCode, existing: existing)
        }

        return friends.count
    }

    private func fetchAvatarIfNeeded(friendCode: String, existing: FriendProfileRow?) async {
        do {
            let result = try await api.getAvatar(friendCode: friendCode, ifNoneMatch: existing?.avatarEtag)
            guard let (data, mime, etag) = result else { return }  // 304 / 404 — оставляем как есть
            try await db.write { db in
                try StatsQueries.updateFriendAvatar(
                    db, friendCode: friendCode, blob: data, mime: mime, etag: etag
                )
            }
        } catch {
            NSLog("ai-stats avatar fetch error for \(friendCode): \(error)")
        }
    }
}
