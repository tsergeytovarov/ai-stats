import Foundation

/// Шпаргалка «какую модель когда» (спека 2.2). Codex — живьём из
/// `~/.codex/models_cache.json` (только `visibility == "list"`, в порядке файла);
/// файла нет / не парсится — Codex-раздел пустой. Claude — статическая таблица.
struct ModelGuide: Equatable {
    struct Entry: Equatable {
        let slug: String
        let description: String
    }

    let codex: [Entry]
    let claude: [Entry]

    /// Claude — фиксированный порядок haiku → sonnet → opus → fable, тексты дословно (спека 2.2).
    static let claudeStatic: [Entry] = [
        Entry(slug: "haiku", description: "поиск по коду, простые правки, саммари"),
        Entry(slug: "sonnet", description: "основная работа: коммиты, PR, рефакторинг"),
        Entry(slug: "opus", description: "архитектура, глубокое ревью, сложный дебаг"),
        Entry(slug: "fable", description: "только самые тяжёлые long-horizon задачи"),
    ]

    /// Собирает шпаргалку. `codexCacheURL` инъектируем; nil → `~/.codex/models_cache.json`.
    static func load(codexCacheURL: URL? = nil) -> ModelGuide {
        let url = codexCacheURL
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        return ModelGuide(codex: loadCodex(url), claude: claudeStatic)
    }

    private static func loadCodex(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { m in
            guard (m["visibility"] as? String) == "list",
                  let slug = m["slug"] as? String
            else { return nil }
            return Entry(slug: slug, description: m["description"] as? String ?? "")
        }
    }
}
