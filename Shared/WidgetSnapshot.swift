import Foundation

/// Mini-snapshot всех метрик за каждый период. Пишется app'ом после sync
/// и читается виджетом из своего sandbox-контейнера.
struct WidgetSnapshot: Codable, Equatable {
    let generatedAt: Date
    let day: PeriodSlice
    let week: PeriodSlice
    let month: PeriodSlice
    let githubEnabled: Bool
    let myFriendCode: String?

    init(
        generatedAt: Date,
        day: PeriodSlice,
        week: PeriodSlice,
        month: PeriodSlice,
        githubEnabled: Bool,
        myFriendCode: String?
    ) {
        self.generatedAt = generatedAt
        self.day = day
        self.week = week
        self.month = month
        self.githubEnabled = githubEnabled
        self.myFriendCode = myFriendCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        self.day = try c.decode(PeriodSlice.self, forKey: .day)
        self.week = try c.decode(PeriodSlice.self, forKey: .week)
        self.month = try c.decode(PeriodSlice.self, forKey: .month)
        self.githubEnabled = try c.decode(Bool.self, forKey: .githubEnabled)
        self.myFriendCode = try c.decodeIfPresent(String.self, forKey: .myFriendCode)
    }

    private enum CodingKeys: String, CodingKey {
        case generatedAt, day, week, month, githubEnabled, myFriendCode
    }

    struct PeriodSlice: Codable, Equatable {
        let aiCost: Double
        let aiCostPrev: Double
        let aiTokens: Int64
        let commits: Int64
        let uniqueRepos: Int
        let topModels: [ModelEntry]
        let leaderboard: LeaderboardSlice?

        init(
            aiCost: Double,
            aiCostPrev: Double,
            aiTokens: Int64,
            commits: Int64,
            uniqueRepos: Int,
            topModels: [ModelEntry],
            leaderboard: LeaderboardSlice?
        ) {
            self.aiCost = aiCost
            self.aiCostPrev = aiCostPrev
            self.aiTokens = aiTokens
            self.commits = commits
            self.uniqueRepos = uniqueRepos
            self.topModels = topModels
            self.leaderboard = leaderboard
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.aiCost = try c.decode(Double.self, forKey: .aiCost)
            self.aiCostPrev = try c.decodeIfPresent(Double.self, forKey: .aiCostPrev) ?? 0
            self.aiTokens = try c.decode(Int64.self, forKey: .aiTokens)
            self.commits = try c.decode(Int64.self, forKey: .commits)
            self.uniqueRepos = try c.decode(Int.self, forKey: .uniqueRepos)
            self.topModels = try c.decode([ModelEntry].self, forKey: .topModels)
            self.leaderboard = try c.decodeIfPresent(LeaderboardSlice.self, forKey: .leaderboard)
        }

        private enum CodingKeys: String, CodingKey {
            case aiCost, aiCostPrev, aiTokens, commits, uniqueRepos, topModels, leaderboard
        }
    }

    struct ModelEntry: Codable, Equatable, Hashable {
        let model: String
        let source: String
        let costUsd: Double
        let inputTokens: Int64
        let outputTokens: Int64
    }

    struct LeaderboardSlice: Codable, Equatable {
        let entries: [Entry]      // <= 8
        let meBelow: Entry?       // nil, если я в top-8 или меня нет вовсе

        struct Entry: Codable, Equatable {
            let rank: Int
            let previousRank: Int?
            let displayName: String
            let tokensTotal: Int64
            let isMe: Bool
        }
    }
}

enum WidgetSnapshotIO {
    /// Bundle id виджет-таргета, в чей контейнер app пишет snapshot.
    static let widgetBundleID = "com.sergeytovarov.aistats.widget"

    static var writeURL: URL {
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())
        return realHome
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/ai-stats")
            .appendingPathComponent("snapshot.json")
    }

    static var readURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ai-stats/snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) throws {
        let url = writeURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: readURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
