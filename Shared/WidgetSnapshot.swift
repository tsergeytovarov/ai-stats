import Foundation

/// Mini-snapshot всех метрик за каждый период. Пишется app'ом после sync
/// и читается виджетом из своего sandbox-контейнера.
struct WidgetSnapshot: Codable, Equatable {
    /// Версия схемы снапшота. 2 — после выпила GitHub/лидерборда. Снапшоты без
    /// этого поля (записанные старым app'ом) трактуются как legacy (версия 1).
    let schemaVersion: Int
    let generatedAt: Date
    let day: PeriodSlice
    let week: PeriodSlice
    let month: PeriodSlice

    init(
        schemaVersion: Int = 2,
        generatedAt: Date,
        day: PeriodSlice,
        week: PeriodSlice,
        month: PeriodSlice
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.day = day
        self.week = week
        self.month = month
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Отсутствие ключа → legacy snapshot (версия 1).
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        self.day = try c.decode(PeriodSlice.self, forKey: .day)
        self.week = try c.decode(PeriodSlice.self, forKey: .week)
        self.month = try c.decode(PeriodSlice.self, forKey: .month)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, day, week, month
    }

    struct PeriodSlice: Codable, Equatable {
        let aiCost: Double
        let aiCostPrev: Double
        let aiTokens: Int64
        let topModels: [ModelEntry]

        init(
            aiCost: Double,
            aiCostPrev: Double,
            aiTokens: Int64,
            topModels: [ModelEntry]
        ) {
            self.aiCost = aiCost
            self.aiCostPrev = aiCostPrev
            self.aiTokens = aiTokens
            self.topModels = topModels
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.aiCost = try c.decode(Double.self, forKey: .aiCost)
            self.aiCostPrev = try c.decodeIfPresent(Double.self, forKey: .aiCostPrev) ?? 0
            self.aiTokens = try c.decode(Int64.self, forKey: .aiTokens)
            self.topModels = try c.decode([ModelEntry].self, forKey: .topModels)
        }

        private enum CodingKeys: String, CodingKey {
            case aiCost, aiCostPrev, aiTokens, topModels
        }
    }

    struct ModelEntry: Codable, Equatable, Hashable {
        let model: String
        let source: String
        let costUsd: Double
        let inputTokens: Int64
        let outputTokens: Int64
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
