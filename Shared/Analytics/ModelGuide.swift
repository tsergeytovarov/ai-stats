import Foundation

/// Шпаргалка «какую модель когда» (спека 2.2). Список Codex-моделей и порядок —
/// из `~/.codex/models_cache.json` (только `visibility == "list"`), но описания
/// свои — курированные, на русском, по задачам (в кэше — маркетинговые blurb'ы
/// на английском, они не говорят ДЛЯ ЧЕГО модель). Для незнакомого slug'а —
/// fallback на текст из кэша. Файла нет / не парсится — Codex-раздел пустой.
/// Claude — статическая таблица.
struct ModelGuide: Equatable {
    struct Entry: Equatable {
        let slug: String
        let description: String
    }

    let codex: [Entry]
    let claude: [Entry]

    /// Курированные русские описания Codex-моделей по задачам (slug → текст).
    static let codexDescriptions: [String: String] = [
        "gpt-5.6-sol":         "самое сложное: архитектура, длинный код, глубокий ресёрч",
        "gpt-5.6-terra":       "повседневная работа: обычные фичи, правки, ревью",
        "gpt-5.6-luna":        "простое и быстрое: мелкие правки, поиск, короткие вопросы",
        "gpt-5.5":             "сложный код и ресёрч (прошлое поколение топовой)",
        "gpt-5.4":             "надёжно для обычного повседневного кода",
        "gpt-5.4-mini":        "простые задачи, где важнее скорость и цена",
        "gpt-5.3-codex-spark": "мгновенные мелкие правки: когда важна скорость, а не глубина",
    ]

    /// Claude — фиксированный порядок haiku → sonnet → opus → fable, задачи, без жаргона.
    static let claudeStatic: [Entry] = [
        Entry(slug: "haiku", description: "поиск по коду, простые правки, саммари"),
        Entry(slug: "sonnet", description: "основная работа: коммиты, PR, рефакторинг"),
        Entry(slug: "opus", description: "архитектура, глубокое ревью, сложный дебаг"),
        Entry(slug: "fable", description: "самые тяжёлые многошаговые задачи"),
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
            // Курированный русский текст; для незнакомой модели — blurb из кэша.
            let desc = codexDescriptions[slug] ?? (m["description"] as? String ?? "")
            return Entry(slug: slug, description: desc)
        }
    }
}
