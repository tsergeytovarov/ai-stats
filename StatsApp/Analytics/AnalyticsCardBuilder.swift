import Foundation
import GRDB

/// Детерминированный расчёт карточки «Аналитика» за фикс-окно 30 дней.
/// Порт experiment3.py: окно, эпохи лимита Codex, кластеры утечек, советы, пороговые
/// состояния. Окно = [начало локального дня (now−30д), now]; таймзона — устройства.
struct AnalyticsCardBuilder {
    var now: () -> Date = Date.init
    var timeZone: TimeZone = .current

    /// Минимальное число ходов суммарно, ниже которого — состояние «мало данных».
    private static let minTurnsForCard = 50

    func build(in db: GRDB.Database) throws -> AnalyticsCard {
        let nowDate = now()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        let windowStart = cal.startOfDay(for: cal.date(byAdding: .day, value: -30, to: nowDate) ?? nowDate)
        let cutoffDay = dayString(windowStart)
        let cutoffTsUTC = utcCutoffString(windowStart)

        let rows = try AnalyticsTurnRow
            .filter(AnalyticsTurnRow.Columns.day >= cutoffDay)
            .fetchAll(db)

        let computedAt = nowDate

        guard !rows.isEmpty else {
            return AnalyticsCard(state: .noData, rangeStart: windowStart, rangeEnd: nowDate,
                                 sources: [], leaks: [], totalExpSavedUsd: 0,
                                 topLeakTitle: nil, advisorComputedAt: computedAt)
        }

        // Эпохи лимита Codex (secondary) в окне.
        let secondary = try AnalyticsRateLimitRow
            .filter(AnalyticsRateLimitRow.Columns.window == "secondary")
            .filter(AnalyticsRateLimitRow.Columns.ts >= cutoffTsUTC)
            .order(AnalyticsRateLimitRow.Columns.ts)
            .fetchAll(db)
            .compactMap(\.usedPercent)
        let (monthLimitPct, avgWeekPct) = codexLimit(secondary)

        // Сводки по источникам (порядок: codex, claude-code).
        var sources: [AnalyticsCard.SourceSummary] = []
        for source in ["codex", "claude-code"] {
            let srcRows = rows.filter { $0.source == source }
            guard !srcRows.isEmpty else { continue }
            let tokens = srcRows.reduce(Int64(0)) {
                $0 + $1.inputTokens + $1.cacheRead + $1.cacheCreate5m + $1.cacheCreate1h + $1.outputTokens
            }
            let cost = srcRows.reduce(0.0) { $0 + $1.costUsd }
            let exp = srcRows.reduce(0.0) { $0 + $1.expSavedUsd }
            sources.append(AnalyticsCard.SourceSummary(
                source: source,
                displayName: Self.displayName(source),
                tokens: tokens,
                costUsd: cost,
                expSavedUsd: exp,
                leakPct: cost > 0 ? exp / cost * 100 : nil,
                avgWeekLimitPct: source == "codex" && monthLimitPct > 0 ? avgWeekPct : nil,
                monthLimitPct: source == "codex" && monthLimitPct > 0 ? monthLimitPct : nil
            ))
        }

        let totalExp = rows.reduce(0.0) { $0 + $1.expSavedUsd }

        // Мало данных — карточка не собирается, поля советника пустые.
        if rows.count < Self.minTurnsForCard {
            return AnalyticsCard(state: .tooFewData, rangeStart: windowStart, rangeEnd: nowDate,
                                 sources: sources, leaks: [], totalExpSavedUsd: totalExp,
                                 topLeakTitle: nil, advisorComputedAt: computedAt)
        }

        let leaks = buildLeaks(rows)
        return AnalyticsCard(state: .ready, rangeStart: windowStart, rangeEnd: nowDate,
                             sources: sources, leaks: leaks, totalExpSavedUsd: totalExp,
                             topLeakTitle: leaks.first?.title, advisorComputedAt: computedAt)
    }

    // MARK: - Кластеры утечек

    private struct ClusterAgg {
        var nTurns = 0
        var expSaved = 0.0
        var modelSaved: [String: Double] = [:]   // модель → Σexp для доминирования
    }

    private func buildLeaks(_ rows: [AnalyticsTurnRow]) -> [AnalyticsCard.LeakCluster] {
        // Группируем по (source, нормализованный ключ).
        var agg: [String: ClusterAgg] = [:]        // "source\u{1}key" → agg
        var keyOf: [String: (source: String, key: String)] = [:]
        for r in rows {
            let key = Self.normPrefix(r.promptHead)
            let composite = r.source + "\u{1}" + key
            var a = agg[composite] ?? ClusterAgg()
            a.nTurns += 1
            a.expSaved += r.expSavedUsd
            a.modelSaved[r.model, default: 0] += r.expSavedUsd
            agg[composite] = a
            keyOf[composite] = (r.source, key)
        }

        var clusters: [AnalyticsCard.LeakCluster] = []
        for (composite, a) in agg {
            // Фильтр: ≥3 ходов И exp_saved строго >$1.00 (сравнение в центах).
            guard a.nTurns >= 3, Int((a.expSaved * 100).rounded()) > 100 else { continue }
            let (source, key) = keyOf[composite]!
            // Доминирующая по экономии модель; tie-break — имя модели для детерминизма.
            let model = a.modelSaved.max { l, r in
                l.value != r.value ? l.value < r.value : l.key > r.key
            }?.key ?? ""
            clusters.append(AnalyticsCard.LeakCluster(
                source: source,
                key: key,
                title: Self.title(forKey: key),
                nTurns: a.nTurns,
                model: model,
                expSavedUsd: a.expSaved,
                adviceText: Self.advice(forKey: key, source: source)
            ))
        }
        // Сортировка: exp_saved DESC, ходы DESC, ключ лексикографически. Топ-3.
        clusters.sort { lhs, rhs in
            if lhs.expSavedUsd != rhs.expSavedUsd { return lhs.expSavedUsd > rhs.expSavedUsd }
            if lhs.nTurns != rhs.nTurns { return lhs.nTurns > rhs.nTurns }
            return lhs.key < rhs.key
        }
        return Array(clusters.prefix(3))
    }

    // MARK: - Лимит Codex (эпохи)

    /// Возвращает (Σэпох за месяц, среднее %/нед). Сброс эпохи при падении >30 п.п.
    /// от максимума; вклад эпохи = max − первое наблюдение.
    private func codexLimit(_ secondary: [Double]) -> (month: Double, avgWeek: Double) {
        var epochs: [Double] = []
        var start: Double?
        var mx: Double = 0
        for sec in secondary {
            if start == nil {
                start = sec
                mx = sec
            } else if mx - sec > 30 {
                epochs.append(mx - start!)
                start = sec
                mx = sec
            } else {
                mx = max(mx, sec)
            }
        }
        if let s = start { epochs.append(mx - s) }
        let month = epochs.reduce(0, +)
        let avgWeek = month > 0 ? month / (30.0 / 7.0) : 0
        return (month, avgWeek)
    }

    // MARK: - Ключи, заголовки, советы

    /// Порт `norm_prefix`: strip+lower; `<command-` → слэш-команды; прочий `<` →
    /// фоновые уведомления; иначе — первые 60 символов.
    static func normPrefix(_ head: String) -> String {
        let h = head.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.hasPrefix("<command-") { return "<слэш-команды>" }
        if h.hasPrefix("<") { return "<фоновые уведомления>" }
        return String(h.prefix(60))
    }

    /// Осмысленный заголовок кластера «по сути», а не сырой повторяющийся промпт.
    /// Роль пайплайна («ты — X») → «Регулярная роль: X»; прочие повторы →
    /// «Повторяющаяся задача: …».
    private static func title(forKey key: String) -> String {
        switch key {
        case "<слэш-команды>": return "Слэш-команды"
        case "<фоновые уведомления>": return "Фоновые уведомления"
        default:
            if key.hasPrefix("ты — ") {
                return "Регулярная роль: \(capFirst(roleName(key)))"
            }
            let preview = key.trimmingCharacters(in: .whitespaces).prefix(36)
            return "Повторяющаяся задача: «\(capFirst(String(preview)))…»"
        }
    }

    /// Имя роли: текст после «ты — » до первой запятой/точки («voice match, …» →
    /// «voice match»; «агрегатор в трубе рерайта. …» → «агрегатор в трубе рерайта»).
    private static func roleName(_ key: String) -> String {
        let rest = key.dropFirst("ты — ".count)
        let end = rest.firstIndex { $0 == "," || $0 == "." } ?? rest.endIndex
        return rest[..<end].trimmingCharacters(in: .whitespaces)
    }

    private static func capFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    /// Совет по типу кластера. Общий смысл — «регулярная задача на дорогой модели,
    /// можно дешевле»; для роли пайплайна — точнее (зафиксировать модель в конфиге).
    private static func advice(forKey key: String, source: String) -> String {
        let cheaper = source == "codex" ? "gpt-5.4" : "sonnet-4-6"
        if key.hasPrefix("ты — ") {
            return "Зафиксируй модель этой роли в конфиге пайплайна: \(cheaper)"
        }
        switch key {
        case "<фоновые уведомления>":
            return "Фоновые уведомления обрабатывай дешёвой моделью"
        case "<слэш-команды>":
            return "Слэш-команды наследуют модель сессии — тяжёлые запускай на средней модели"
        default:
            return "Регулярная задача на дорогой модели — попробуй \(cheaper)"
        }
    }

    static func displayName(_ source: String) -> String {
        switch source {
        case "codex": return "Codex"
        case "claude-code": return "Claude Code"
        default: return source
        }
    }

    // MARK: - Даты окна

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// UTC-строка границы окна для сравнения с ts лимитов (как CUTOFF_STR в прототипе).
    private func utcCutoffString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
