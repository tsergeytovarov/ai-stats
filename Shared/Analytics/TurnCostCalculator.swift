import Foundation

/// Расчёт стоимости хода, минимально достаточной ступени (эвристика) и ожидаемой
/// экономии. Порт `heur_tier`, `cost`, а также формулы exp_saved из experiment3.py.
enum TurnCostCalculator {

    /// Итог расчёта по «фичам» хода — переиспользуется при ингесте и при пересчёте
    /// in-place после смены pricing_version (без реингеста).
    struct Verdict: Equatable {
        var costUsd: Double
        var heurTier: Int?
        var cfModel: String?
        var cfUsd: Double?
        var expSavedUsd: Double
    }

    /// Стоп-лист коротких подтверждений/реплик (нормализованные слова, lowercase).
    private static let confirmationWords: Set<String> = [
        "да", "ага", "угу", "ок", "окей", "нет", "готово", "ясно", "понял", "поняла",
        "спс", "спасибо", "yes", "no", "ok", "okay", "yep", "y", "n"
    ]

    /// Ход-«filler»: подтверждение/реплика внутри уже идущей сессии, а не отдельный
    /// запрос. Его нельзя перекинуть на другую модель (он продолжает сессию), поэтому
    /// он не может быть «утечкой» — exp_saved = 0. Правило: нет букв вообще («1»,
    /// «1 — 6 2 — 10», «+») ИЛИ все слова из стоп-листа подтверждений («да», «ок ок»).
    static func isFiller(_ promptHead: String) -> Bool {
        let s = promptHead.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return true }
        // Спец-обёртки (task-notification / слэш-команды) — не filler, у них своя судьба.
        if s.hasPrefix("<") { return false }
        let hasLetters = s.contains { $0.isLetter }
        if !hasLetters { return true }
        let words = s.split { !$0.isLetter }.map(String.init)
        return !words.isEmpty && words.allSatisfy { confirmationWords.contains($0) }
    }

    /// Минимально достаточная ступень по форме хода (спека 5.3). Вызывается только
    /// для T0-моделей; для не-T0 гейт стоит в `verdict`.
    static func heurTier(nEdits: Int64, nTools: Int64, outTok: Int64, promptChars: Int64) -> Int {
        if nEdits == 0 && nTools == 0 && outTok < 800 && promptChars < 1200 { return 2 }
        if nEdits == 0 && nTools <= 4 && outTok < 4000 { return 1 }
        return 0
    }

    private static func cost(
        model: String,
        inputTokens: Int64, outputTokens: Int64,
        cacheRead: Int64, cacheCreate5m: Int64, cacheCreate1h: Int64
    ) -> Double {
        PricingTable.cost(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheRead,
            cacheCreateTokens: cacheCreate5m + cacheCreate1h,
            cacheCreate1hTokens: cacheCreate1h
        )
    }

    /// Полный расчёт вердикта по сырым полям хода.
    static func verdict(
        source: String, model: String,
        nEdits: Int64, nTools: Int64,
        inputTokens: Int64, outputTokens: Int64,
        cacheRead: Int64, cacheCreate5m: Int64, cacheCreate1h: Int64,
        promptChars: Int64, promptHead: String
    ) -> Verdict {
        let c = cost(model: model,
                     inputTokens: inputTokens, outputTokens: outputTokens,
                     cacheRead: cacheRead, cacheCreate5m: cacheCreate5m, cacheCreate1h: cacheCreate1h)

        // Гейт: вердикт только T0-ходам. Filler-подтверждения — не утечка (нельзя
        // переключить модель у реплики, продолжающей сессию) → exp_saved 0.
        guard ModelLadder.isT0(model), !isFiller(promptHead) else {
            return Verdict(costUsd: c, heurTier: nil, cfModel: nil, cfUsd: nil, expSavedUsd: 0)
        }

        let tier = heurTier(nEdits: nEdits, nTools: nTools, outTok: outputTokens, promptChars: promptChars)

        var cfModel: String?
        var cfUsd: Double?
        if tier == 1 || tier == 2 {
            cfModel = ModelLadder.targetModel(source: source, tier: tier)
            if let cfModel {
                cfUsd = cost(model: cfModel,
                             inputTokens: inputTokens, outputTokens: outputTokens,
                             cacheRead: cacheRead, cacheCreate5m: cacheCreate5m, cacheCreate1h: cacheCreate1h)
            }
        }

        // Формула ожидаемой экономии (спека 5.3 / experiment3.py):
        //   tier 0 → cost × judgeRatioT0(source); tier 1|2 → max(0, cost − cf_usd).
        let expSaved: Double
        if tier == 0 {
            expSaved = c * ModelLadder.judgeRatioT0(source: source)
        } else {
            expSaved = max(0, c - (cfUsd ?? c))
        }

        return Verdict(costUsd: c, heurTier: tier, cfModel: cfModel, cfUsd: cfUsd, expSavedUsd: expSaved)
    }

    /// Обогащает `ParsedTurn` в строку БД: проставляет day, origin и поля вердикта.
    /// `timeZone` — локальная таймзона устройства (санкционированное расхождение с
    /// прото-хардкодом Europe/Moscow).
    static func enrich(_ turn: ParsedTurn, timeZone: TimeZone = .current) -> AnalyticsTurnRow {
        let v = verdict(
            source: turn.source, model: turn.model,
            nEdits: turn.nEdits, nTools: turn.nToolCalls,
            inputTokens: turn.inputTokens, outputTokens: turn.outputTokens,
            cacheRead: turn.cacheRead, cacheCreate5m: turn.cacheCreate5m, cacheCreate1h: turn.cacheCreate1h,
            promptChars: turn.promptChars, promptHead: turn.promptHead
        )
        return AnalyticsTurnRow(
            id: nil,
            source: turn.source,
            ts: turn.ts,
            day: AnalyticsTime.day(fromISO: turn.ts, timeZone: timeZone),
            session: turn.session,
            project: turn.project,
            model: turn.model,
            effort: turn.effort,
            origin: turn.origin,
            promptHead: turn.promptHead,
            promptChars: turn.promptChars,
            nRequests: turn.nRequests,
            nToolCalls: turn.nToolCalls,
            nEdits: turn.nEdits,
            inputTokens: turn.inputTokens,
            cacheRead: turn.cacheRead,
            cacheCreate5m: turn.cacheCreate5m,
            cacheCreate1h: turn.cacheCreate1h,
            outputTokens: turn.outputTokens,
            costUsd: v.costUsd,
            heurTier: v.heurTier,
            cfModel: v.cfModel,
            cfUsd: v.cfUsd,
            expSavedUsd: v.expSavedUsd
        )
    }

    /// Пересчёт вердикта in-place по уже хранимым полям строки (смена pricing_version).
    static func recompute(_ row: inout AnalyticsTurnRow) {
        let v = verdict(
            source: row.source, model: row.model,
            nEdits: row.nEdits, nTools: row.nToolCalls,
            inputTokens: row.inputTokens, outputTokens: row.outputTokens,
            cacheRead: row.cacheRead, cacheCreate5m: row.cacheCreate5m, cacheCreate1h: row.cacheCreate1h,
            promptChars: row.promptChars, promptHead: row.promptHead
        )
        row.costUsd = v.costUsd
        row.heurTier = v.heurTier
        row.cfModel = v.cfModel
        row.cfUsd = v.cfUsd
        row.expSavedUsd = v.expSavedUsd
    }
}

/// Парсинг ISO-таймстампа транскрипта → локальный календарный день (yyyy-MM-dd).
enum AnalyticsTime {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(fromISO ts: String) -> Date? {
        isoFractional.date(from: ts) ?? isoPlain.date(from: ts)
    }

    /// Локальный день записи. При невалидном ts — пустая строка (ход отфильтруется
    /// оконным запросом карточки; прототип такие ходы пропускает целиком).
    static func day(fromISO ts: String, timeZone: TimeZone) -> String {
        guard let d = date(fromISO: ts) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
