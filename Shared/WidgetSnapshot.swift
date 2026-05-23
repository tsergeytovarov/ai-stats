import Foundation

/// Mini-snapshot всех метрик за каждый период. Пишется app'ом после sync
/// и читается виджетом из своего sandbox-контейнера. Это обход того что
/// App Group entitlement требует Personal Team подпись, которой у нас нет.
struct WidgetSnapshot: Codable, Equatable {
    let generatedAt: Date
    let day: PeriodSlice
    let week: PeriodSlice
    let month: PeriodSlice
    let githubEnabled: Bool

    struct PeriodSlice: Codable, Equatable {
        let aiCost: Double
        let aiTokens: Int64
        let commits: Int64
        let uniqueRepos: Int
        let topModels: [ModelEntry]
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
    /// Должен совпадать с PRODUCT_BUNDLE_IDENTIFIER StatsWidget в project.yml.
    static let widgetBundleID = "com.sergeytovarov.aistats.widget"

    /// Путь до snapshot.json внутри sandbox-контейнера виджета.
    /// App (unsandboxed) кладёт сюда напрямую, виджет (sandboxed) видит этот
    /// путь как свой `~/Library/Application Support/`.
    static var snapshotURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/ai-stats")
            .appendingPathComponent("snapshot.json")
    }

    /// Пишется app'ом. Создаёт промежуточные директории если их нет.
    static func write(_ snapshot: WidgetSnapshot) throws {
        let url = snapshotURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    /// Читается виджетом. Возвращает nil если файла нет (snapshot ещё не написан).
    static func read() -> WidgetSnapshot? {
        let url = snapshotURL
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
