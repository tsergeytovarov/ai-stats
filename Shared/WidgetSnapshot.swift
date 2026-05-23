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

    /// Путь для записи snapshot'а из app (unsandboxed): абсолютный путь
    /// до Application Support в контейнере виджета.
    static var writeURL: URL {
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory())
        return realHome
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/Library/Application Support/ai-stats")
            .appendingPathComponent("snapshot.json")
    }

    /// Путь для чтения snapshot'а из виджета (sandboxed): widget видит
    /// свой контейнер как обычный ~/Library/Application Support.
    static var readURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ai-stats/snapshot.json")
    }

    /// Пишется app'ом. Создаёт промежуточные директории если их нет.
    static func write(_ snapshot: WidgetSnapshot) throws {
        let url = writeURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    /// Читается виджетом. Возвращает nil если файла нет.
    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: readURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
