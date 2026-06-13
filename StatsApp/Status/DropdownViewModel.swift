import Foundation
import Combine
import SwiftUI
import GRDB
import os.log

// Period enum lives in Shared/Period.swift — accessible to both app and widget targets.

extension Period {
    var titleKey: LocalizedStringKey {
        switch self {
        case .day: return "period.day"
        case .week: return "period.week"
        case .month: return "period.month"
        }
    }
}

enum DropdownSection: String, CaseIterable, Identifiable {
    case ai
    case github
    case leaderboard

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ai: return "AI"
        case .github: return "GitHub"
        case .leaderboard: return "Лидерборд"
        }
    }
}

@MainActor
final class DropdownViewModel: ObservableObject {
    private let db: any DatabaseReader
    private weak var syncCoordinator: SyncCoordinator?
    private let api: AiuseAPIClient?
    private let hasAccount: () -> Bool
    let githubEnabled: Bool
    /// Когда true — loadLeaderboard читает ТОЛЬКО из локального кэша, не дёргает aiuse-сервер.
    /// Нужно для скриншотов с seed-данными (см. scripts/seed-demo-leaderboard.py).
    let demoMode: Bool

    @Published var period: Period = .day {
        didSet {
            // reload — синхронный (БД локальная, запросы — миллисекунды).
            // Раньше был Task { await reload() } — при переключении period в
            // popover'е async-Task не успевал обновить @Published так, чтобы
            // NSPopover/SwiftUI отрисовал свежее значение в том же tick'е.
            // Crumb (берёт period напрямую) обновлялся, а HeroNumber/topModels
            // (берут aiTotals/topModels) — нет, пока popover не переоткроют.
            reloadSync()
            Task { await loadLeaderboard() }
        }
    }
    @Published var section: DropdownSection = .ai
    @Published var aiTotals: AITotals = .init(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0)
    @Published var aiTotalsPrev: AITotals = .init(totalCost: 0, totalInputTokens: 0, totalOutputTokens: 0)
    @Published var bySource: [SourceTotal] = []
    @Published var topModels: [ModelTotal] = []
    @Published var githubTotals: GitHubTotals = .init(totalCommits: 0, uniqueRepos: 0)
    @Published var loc: GitHubLOC = GitHubLOC(additions: 0, deletions: 0)
    @Published var topRepos: [RepoTotal] = []
    @Published var sparklineSeries: [Double] = []
    @Published var additionsSeries: [Double] = []
    @Published var lastSyncDescription: String = "never"

    // Leaderboard (v0.3.0)
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var leaderboardError: String?
    /// true — сервер скрыл борду из-за выключенного шаринга (403). Не ошибка:
    /// UI показывает подсказку «включи шаринг», а не красный error.
    @Published var leaderboardSharingOff: Bool = false
    @Published var leaderboardLoading: Bool = false
    @Published var friendAvatars: [String: Data] = [:]   // friend_code → avatar bytes

    init(db: any DatabaseReader,
         syncCoordinator: SyncCoordinator,
         api: AiuseAPIClient? = nil,
         hasAccount: @escaping () -> Bool = { false },
         githubEnabled: Bool = true,
         demoMode: Bool = false) {
        self.db = db
        self.syncCoordinator = syncCoordinator
        self.api = api
        self.hasAccount = hasAccount
        self.githubEnabled = githubEnabled
        self.demoMode = demoMode
    }

    /// Async-обёртка над reloadSync. Сохранена для существующих call site'ов
    /// (initial app start, refresh button) — там awaiт удобно.
    func reload() async {
        reloadSync()
    }

    /// Синхронный read из БД + обновление всех @Published. Делается в одном
    /// MainActor tick'е чтобы SwiftUI гарантированно подхватил все изменения
    /// в одном цикле re-render'а. БД локальная (GRDB DatabasePool), запросы
    /// порядка миллисекунд — sync read не блокирует UI заметно.
    func reloadSync() {
        let now = Date()
        let periodDays = DateUtils.daysRange(endingAt: now, lookback: period.lookbackDays)
        let prevPeriodDays = DateUtils.previousPeriodDays(endingAt: now, lookback: period.lookbackDays)
        let sparkDays = DateUtils.daysRange(endingAt: now, lookback: 29)

        AppLogger.sync.info(
            "reloadSync period=\(self.period.rawValue, privacy: .public) days=\(periodDays.count, privacy: .public)"
        )

        do {
            let snapshot = try db.read { db -> (AITotals, AITotals, [SourceTotal], [ModelTotal], GitHubTotals, GitHubLOC, [RepoTotal], [Double], [Double]) in
                let totals = try StatsQueries.aiTotals(in: db, days: periodDays)
                let totalsPrev = try StatsQueries.aiTotals(in: db, days: prevPeriodDays)
                let bySource = try StatsQueries.aiTotalsBySource(in: db, days: periodDays)
                let models = try StatsQueries.topModels(in: db, days: periodDays, limit: 5)
                let gh = try StatsQueries.githubTotals(in: db, days: periodDays)
                let loc = try StatsQueries.githubLOC(in: db, days: periodDays)
                let repos = try StatsQueries.topRepos(in: db, days: periodDays, limit: 5)
                let costSeries = try StatsQueries.dailyAICostSeries(in: db, days: sparkDays)
                let addsSeries = try StatsQueries.dailyAdditionsSeries(in: db, days: sparkDays)
                return (totals, totalsPrev, bySource, models, gh, loc, repos, costSeries, addsSeries)
            }
            self.aiTotals = snapshot.0
            self.aiTotalsPrev = snapshot.1
            self.bySource = snapshot.2
            self.topModels = snapshot.3
            self.githubTotals = snapshot.4
            self.loc = snapshot.5
            self.topRepos = snapshot.6
            self.sparklineSeries = snapshot.7
            self.additionsSeries = snapshot.8
            self.lastSyncDescription = relativeDescription(for: syncCoordinator?.lastSyncAt.values.max())
            AppLogger.sync.info(
                "reload done period=\(self.period.rawValue, privacy: .public) totalCost=\(snapshot.0.totalCost, privacy: .public)"
            )
        } catch {
            // GRDB errors могут содержать SQL — .private. Тип ошибки тоже не делаем .public,
            // чтобы не светить internals в Console.app.
            AppLogger.sync.error("Reload failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func todayCost() async -> Double {
        let today = [DateUtils.isoDayLocal(Date())]
        return (try? await db.read { db in try StatsQueries.aiTotals(in: db, days: today).totalCost }) ?? 0
    }

    func triggerSync(sources: [(name: String, fetchers: [any Fetcher])]) async {
        guard let coord = syncCoordinator else { return }
        for (name, fetchers) in sources {
            try? await coord.runOnce(source: name, fetchers: fetchers)
        }
        await reload()
        await loadLeaderboard()
    }

    func loadLeaderboard() async {
        guard let api, hasAccount() else {
            leaderboard = []
            leaderboardError = nil
            leaderboardSharingOff = false
            return
        }
        leaderboardLoading = true
        defer { leaderboardLoading = false }
        leaderboardError = nil
        leaderboardSharingOff = false

        let apiPeriod: String
        switch period {
        case .day: apiPeriod = "day"
        case .week: apiPeriod = "week"
        case .month: apiPeriod = "month"
        }

        // Сначала кэш (мгновенный рендер если есть)
        if let cached = try? await db.read({ try StatsQueries.loadLeaderboardCache($0, period: apiPeriod) }),
           let data = cached.payloadJson.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(LeaderboardResponse.self, from: data) {
            leaderboard = decoded.entries
        }

        // В demo_mode НЕ дёргаем сервер — иначе seed-данные затрутся real-ответом.
        // Cached-данные из leaderboard_cache уже загружены выше — этого достаточно.
        if demoMode {
            await reloadAvatars()
            return
        }

        // Затем свежее с сервера. На ошибке оставляем cached (если был).
        do {
            let resp = try await api.getLeaderboard(period: apiPeriod)
            leaderboard = resp.entries
            // Параллельно сохраняем в локальный кэш + подгружаем аватарки
            if let data = try? JSONEncoder().encode(resp),
               let json = String(data: data, encoding: .utf8),
               let writer = db as? any DatabaseWriter {
                try? await writer.write { try StatsQueries.saveLeaderboardCache($0, period: apiPeriod, payloadJson: json) }
            }
        } catch AiuseAPIError.http(403, _) {
            // sharing_enabled=false на сервере — борда намеренно скрыта (free-rider
            // protection), это не ошибка. Показываем подсказку «включи шаринг» и
            // прячем возможный устаревший кэш чужих результатов.
            leaderboard = []
            leaderboardError = nil
            leaderboardSharingOff = true
        } catch {
            // Если кэша не было — показываем ошибку. Иначе тихо живём с кэшем.
            if leaderboard.isEmpty {
                leaderboardError = "Не удалось загрузить лидерборд: \(error.localizedDescription)"
            }
        }

        await reloadAvatars()
    }

    /// Подгружает avatar_blob из friend_profiles + my_profile для всех entries
    /// в текущем лидерборде. Свой код живёт в my_profile, не в friend_profiles —
    /// без отдельного fetch'а моя строка осталась бы без аватарки.
    func reloadAvatars() async {
        let codes = leaderboard.map { $0.friendCode }
        guard !codes.isEmpty else { friendAvatars = [:]; return }
        let rows: [FriendProfileRow] = (try? await db.read { db in
            try FriendProfileRow.filter(codes.contains(FriendProfileRow.Columns.friendCode)).fetchAll(db)
        }) ?? []
        var map: [String: Data] = [:]
        for row in rows {
            if let blob = row.avatarBlob { map[row.friendCode] = blob }
        }
        // Моя строка — отдельный источник правды.
        if let me = try? await db.read({ try StatsQueries.loadMyProfile($0) }),
           let blob = me.avatarBlob,
           codes.contains(me.friendCode) {
            map[me.friendCode] = blob
        }
        friendAvatars = map
    }

    private func relativeDescription(for date: Date?) -> String {
        guard let date else { return NSLocalizedString("unit.never", comment: "") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
