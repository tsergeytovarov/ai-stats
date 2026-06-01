import Foundation
import GRDB
import WidgetKit
#if canImport(AppKit)
import AppKit
#endif
import os.log

/// Управляет периодической синхронизацией. Single-flight per source.
@MainActor
final class SyncCoordinator {
    private let db: any DatabaseWriter
    private let now: () -> Date
    private let snapshotSyncer: SnapshotSyncer?
    private let friendsPullSyncer: FriendsPullSyncer?
    private let leaderboardPullSyncer: LeaderboardPullSyncer?
    /// Тесты прокидывают свой NotificationCenter + имя, чтобы шлать synthetic wake.
    /// В проде nil — берётся NSWorkspace.shared.notificationCenter в installWakeObserverIfNeeded().
    private let testWakeCenter: NotificationCenter?
    private let testWakeName: Notification.Name?
    private var inFlight: Set<String> = []
    private var dispatchTimer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private var wakeObserverCenter: NotificationCenter?
    private var configuredSources: [(name: String, fetchers: [any Fetcher])] = []
    private var configuredInterval: TimeInterval = 0
    private(set) var lastSyncAt: [String: Date] = [:]

    init(db: any DatabaseWriter,
         snapshotSyncer: SnapshotSyncer? = nil,
         friendsPullSyncer: FriendsPullSyncer? = nil,
         leaderboardPullSyncer: LeaderboardPullSyncer? = nil,
         testWakeCenter: NotificationCenter? = nil,
         testWakeName: Notification.Name? = nil,
         now: @escaping () -> Date = Date.init) {
        self.db = db
        self.snapshotSyncer = snapshotSyncer
        self.friendsPullSyncer = friendsPullSyncer
        self.leaderboardPullSyncer = leaderboardPullSyncer
        self.testWakeCenter = testWakeCenter
        self.testWakeName = testWakeName
        self.now = now
    }

    deinit {
        if let wakeObserver, let wakeObserverCenter {
            wakeObserverCenter.removeObserver(wakeObserver)
        }
        dispatchTimer?.cancel()
    }

    func startTimer(interval: TimeInterval, sources: [(name: String, fetchers: [any Fetcher])]) {
        dispatchTimer?.cancel()
        configuredSources = sources
        configuredInterval = interval

        // DispatchSourceTimer на main queue вместо Timer.scheduledTimer:
        // 1. Не зависит от RunLoop modes — пока main queue жива, timer стреляет.
        // 2. Лучше переживает sleep/wake циклы macOS, чем Timer на main RunLoop
        //    (который после long sleep мог замолкать на старых билдах).
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.runAllSources() }
        }
        t.resume()
        dispatchTimer = t

        // Подписка на wake. После долгого sleep'а Mac'а штатный таймер мог
        // пропустить интервалы — нотификация триггерит немедленный sync,
        // чтобы виджет/popover не сидели на устаревших данных полчаса.
        installWakeObserverIfNeeded()
    }

    func stopTimer() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
        if let wakeObserver, let wakeObserverCenter {
            wakeObserverCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
            self.wakeObserverCenter = nil
        }
    }

    /// Вызывает `runOnce` для всех configured-источников. Используется и тиком
    /// таймера, и обработчиком wake-нотификации.
    func runAllSources() async {
        for (name, fetchers) in configuredSources {
            try? await runOnce(source: name, fetchers: fetchers)
        }
    }

    private func installWakeObserverIfNeeded() {
        guard wakeObserver == nil else { return }
        let center: NotificationCenter
        let name: Notification.Name
        if let testWakeCenter, let testWakeName {
            center = testWakeCenter
            name = testWakeName
        } else {
            #if canImport(AppKit)
            center = NSWorkspace.shared.notificationCenter
            name = NSWorkspace.didWakeNotification
            #else
            return
            #endif
        }
        wakeObserverCenter = center
        wakeObserver = center.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Запускаем sync через MainActor — наш state @MainActor-isolated.
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppLogger.sync.info("Wake notification — forcing sync for all sources")
                await self.runAllSources()
            }
        }
    }

    func runOnce(source: String, fetchers: [any Fetcher]) async throws {
        guard !inFlight.contains(source) else { return }
        inFlight.insert(source)
        defer { inFlight.remove(source) }

        let since = try syncWindowStart(source: source)
        var capturedError: Error?

        for fetcher in fetchers {
            do {
                let result = try await fetcher.fetch(since: since)
                try persist(result)
            } catch {
                capturedError = error
                // source = "ccusage"/"github" (public). error может содержать body/stderr (private).
                AppLogger.sync.error(
                    "Sync failed [\(source, privacy: .public)]: \(error.localizedDescription, privacy: .private)"
                )
            }
        }

        try recordSyncState(source: source, error: capturedError)
        lastSyncAt[source] = now()
        try? buildAndWriteWidgetSnapshot()
        WidgetCenter.shared.reloadAllTimelines()

        // После ccusage-sync пушим snapshot'ы на aiuse-сервер, потом тянем
        // обновлённый список друзей и лидерборд. Ошибки не ронят общий тик.
        if source == "ccusage" {
            if let syncer = snapshotSyncer {
                do { _ = try await syncer.runOnce() }
                catch {
                    AppLogger.aiuse.error("Snapshot sync failed: \(error.localizedDescription, privacy: .private)")
                }
            }
            if let pullSyncer = friendsPullSyncer {
                do { _ = try await pullSyncer.runOnce() }
                catch {
                    AppLogger.aiuse.error("Friends pull failed: \(error.localizedDescription, privacy: .private)")
                }
            }
            if let lbSyncer = leaderboardPullSyncer {
                do { _ = try await lbSyncer.runOnce() }
                catch {
                    AppLogger.aiuse.error("Leaderboard pull failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
    }

    /// Считает текущие totals за Day/Week/Month, prev-cost для дельт, и leaderboard slice.
    /// Чистая функция: не пишет на диск.
    internal func buildSnapshot() throws -> WidgetSnapshot {
        let nowDate = now()
        let dayDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.day.lookbackDays)
        let weekDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.week.lookbackDays)
        let monthDays = DateUtils.daysRange(endingAt: nowDate, lookback: Period.month.lookbackDays)
        let dayPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.day.lookbackDays)
        let weekPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.week.lookbackDays)
        let monthPrev = DateUtils.previousPeriodDays(endingAt: nowDate, lookback: Period.month.lookbackDays)

        struct BuildResult {
            let day: WidgetSnapshot.PeriodSlice
            let week: WidgetSnapshot.PeriodSlice
            let month: WidgetSnapshot.PeriodSlice
            let myFriendCode: String?
        }

        let result: BuildResult = try db.read { db in
            let myCode = try StatsQueries.loadMyProfile(db)?.friendCode
            return BuildResult(
                day: try Self.makeSlice(in: db, days: dayDays, prevDays: dayPrev, leaderboardPeriod: "day", myFriendCode: myCode),
                week: try Self.makeSlice(in: db, days: weekDays, prevDays: weekPrev, leaderboardPeriod: "week", myFriendCode: myCode),
                month: try Self.makeSlice(in: db, days: monthDays, prevDays: monthPrev, leaderboardPeriod: "month", myFriendCode: myCode),
                myFriendCode: myCode
            )
        }

        let anyCommits = result.day.commits + result.week.commits + result.month.commits
        let anyRepos = max(result.day.uniqueRepos, result.week.uniqueRepos, result.month.uniqueRepos)

        return WidgetSnapshot(
            generatedAt: nowDate,
            day: result.day,
            week: result.week,
            month: result.month,
            githubEnabled: anyCommits > 0 || anyRepos > 0,
            myFriendCode: result.myFriendCode
        )
    }

    /// Вычисляет snapshot и пишет его в контейнер виджета.
    private func buildAndWriteWidgetSnapshot() throws {
        let snapshot = try buildSnapshot()
        try WidgetSnapshotIO.write(snapshot)
        try? syncAvatarsToWidgetContainer(snapshot: snapshot)
    }

    /// Копирует blob'ы из my_profile/friend_profiles в widget sandbox для всех
    /// friend_code, упомянутых в snapshot.leaderboard. Widget сам читает blob'ы
    /// по имени файла. Тащить blob'ы внутрь snapshot.json нерационально —
    /// 50KB×8 = ~400KB JSON на каждый timeline reload.
    private func syncAvatarsToWidgetContainer(snapshot: WidgetSnapshot) throws {
        // Собираем уникальные friend_code из всех периодов
        var codes: Set<String> = []
        for period in [snapshot.day, snapshot.week, snapshot.month] {
            guard let lb = period.leaderboard else { continue }
            for e in lb.entries where !e.friendCode.isEmpty { codes.insert(e.friendCode) }
            if let me = lb.meBelow, !me.friendCode.isEmpty { codes.insert(me.friendCode) }
        }
        guard !codes.isEmpty else {
            WidgetSnapshotIO.pruneAvatars(keep: [])
            return
        }

        // Загружаем blob'ы за один read и пишем в widget container
        struct AvatarBlob { let code: String; let data: Data }
        let blobs: [AvatarBlob] = try db.read { db in
            var result: [AvatarBlob] = []
            // friend_profiles
            let friends = try FriendProfileRow
                .filter(codes.contains(FriendProfileRow.Columns.friendCode))
                .fetchAll(db)
            for row in friends {
                if let blob = row.avatarBlob {
                    result.append(AvatarBlob(code: row.friendCode, data: blob))
                }
            }
            // my_profile отдельно — лежит в другой таблице
            if let me = try StatsQueries.loadMyProfile(db),
               codes.contains(me.friendCode),
               let blob = me.avatarBlob {
                result.append(AvatarBlob(code: me.friendCode, data: blob))
            }
            return result
        }

        for b in blobs {
            try? WidgetSnapshotIO.writeAvatar(friendCode: b.code, data: b.data)
        }
        WidgetSnapshotIO.pruneAvatars(keep: codes)
    }

    private static func makeSlice(
        in db: GRDB.Database,
        days: [String],
        prevDays: [String],
        leaderboardPeriod: String,
        myFriendCode: String?
    ) throws -> WidgetSnapshot.PeriodSlice {
        let totals = try StatsQueries.aiTotals(in: db, days: days)
        let totalsPrev = try StatsQueries.aiTotals(in: db, days: prevDays)
        let gh = try StatsQueries.githubTotals(in: db, days: days)
        let models = try StatsQueries.topModels(in: db, days: days, limit: 4)
        let lb = try Self.makeLeaderboardSlice(in: db, period: leaderboardPeriod, myFriendCode: myFriendCode)

        return WidgetSnapshot.PeriodSlice(
            aiCost: totals.totalCost,
            aiCostPrev: totalsPrev.totalCost,
            aiTokens: totals.totalInputTokens + totals.totalOutputTokens,
            commits: gh.totalCommits,
            uniqueRepos: gh.uniqueRepos,
            topModels: models.map {
                WidgetSnapshot.ModelEntry(
                    model: $0.model,
                    source: $0.source,
                    costUsd: $0.costUsd,
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens
                )
            },
            leaderboard: lb
        )
    }

    /// Парсит leaderboard_cache.payload_json в LeaderboardSlice: top-8 entries + meBelow если я ниже.
    private static func makeLeaderboardSlice(
        in db: GRDB.Database, period: String, myFriendCode: String?
    ) throws -> WidgetSnapshot.LeaderboardSlice? {
        guard let row = try StatsQueries.loadLeaderboardCache(db, period: period) else { return nil }
        guard let data = row.payloadJson.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        let resp: LeaderboardResponse
        do {
            resp = try decoder.decode(LeaderboardResponse.self, from: data)
        } catch {
            AppLogger.widget.error(
                "Leaderboard decode failed [\(period, privacy: .public)]: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }

        func mapEntry(_ e: LeaderboardEntry) -> WidgetSnapshot.LeaderboardSlice.Entry {
            WidgetSnapshot.LeaderboardSlice.Entry(
                rank: e.rank,
                previousRank: e.previousRank,
                friendCode: e.friendCode,
                displayName: e.displayName,
                tokensTotal: e.tokensTotal,
                isMe: e.isMe
            )
        }

        let topEntries = Array(resp.entries.prefix(8))
        let top8 = topEntries.map(mapEntry)

        let meBelow: WidgetSnapshot.LeaderboardSlice.Entry?
        if let myCode = myFriendCode,
           !topEntries.contains(where: { $0.friendCode == myCode }),
           let mine = resp.entries.first(where: { $0.friendCode == myCode })
        {
            meBelow = mapEntry(mine)
        } else {
            meBelow = nil
        }

        return WidgetSnapshot.LeaderboardSlice(entries: Array(top8), meBelow: meBelow)
    }

    private func syncWindowStart(source: String) throws -> Date {
        let cal = Calendar(identifier: .gregorian)
        let state = try db.read { db in try SyncStateRow.filter(SyncStateRow.Columns.source == source).fetchOne(db) }
        let lookbackDays = state == nil ? 365 : 7
        return cal.date(byAdding: .day, value: -lookbackDays, to: now())!
    }

    private func persist(_ result: FetchResult) throws {
        try db.write { db in
            switch result {
            case .aiUsage(let payload):
                for row in payload.dayRows { try NeverDecreaseUpserter.upsertAIUsage(row, in: db) }
                for row in payload.modelRows { try NeverDecreaseUpserter.upsertAIUsageModel(row, in: db) }
            case .github(let payload):
                for row in payload.dailyCommits { try NeverDecreaseUpserter.upsertGitHub(row, in: db) }
                for row in payload.dailyLOC { try NeverDecreaseUpserter.upsertGitHubLOCDaily(row, in: db) }
            }
        }
    }

    private func recordSyncState(source: String, error: Error?) throws {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: now())
        let state = SyncStateRow(source: source, lastSyncAt: nowString, lastError: error?.localizedDescription)
        try db.write { db in
            try state.save(db)
        }
    }
}
