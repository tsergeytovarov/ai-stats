import Foundation
import GRDB

/// Инкрементальный ингестор транскриптов Claude Code и Codex.
/// Инкрементальность — на уровне файлов: файл перечитывается целиком, только если
/// изменились mtime/size (`analytics_ingest_state`). Окном НЕ режет — пишет всю
/// историю. При смене `pricing_version` пересчитывает вердикты in-place без реингеста.
struct AnalyticsIngestor {

    /// Версия расчёта (PricingTable + судейские коэффициенты). Бамп → пересчёт in-place.
    // Версия расчёта вердикта: бустать при ЛЮБОЙ смене логики cost/tier/exp
    // (не только прайса) — иначе хранимые в analytics_turns вердикты остаются
    // старыми. v2: filler-гейт подтверждений (exp_saved 0 для «да»/«ок»/«1»).
    static let currentPricingVersion = "2"

    let claudeProjectsBaseURL: URL
    let codexSessionsBaseURL: URL
    let dbWriter: any DatabaseWriter
    let timeZone: TimeZone
    let now: () -> Date
    let pricingVersion: String

    init(
        dbWriter: any DatabaseWriter,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        pricingVersion: String = AnalyticsIngestor.currentPricingVersion
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeProjectsBaseURL = home.appendingPathComponent(".claude/projects")
        self.codexSessionsBaseURL = home.appendingPathComponent(".codex/sessions")
        self.dbWriter = dbWriter
        self.timeZone = timeZone
        self.now = now
        self.pricingVersion = pricingVersion
    }

    init(
        claudeProjectsBaseURL: URL,
        codexSessionsBaseURL: URL,
        dbWriter: any DatabaseWriter,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        pricingVersion: String = AnalyticsIngestor.currentPricingVersion
    ) {
        self.claudeProjectsBaseURL = claudeProjectsBaseURL
        self.codexSessionsBaseURL = codexSessionsBaseURL
        self.dbWriter = dbWriter
        self.timeZone = timeZone
        self.now = now
        self.pricingVersion = pricingVersion
    }

    private enum Kind { case claude, codex }

    func ingest() async throws {
        try await dbWriter.write { db in
            try recomputeIfPricingChanged(db)
            try ingestSource(db, base: claudeProjectsBaseURL, kind: .claude)
            try ingestSource(db, base: codexSessionsBaseURL, kind: .codex)
        }
    }

    // MARK: - Pricing version

    /// Смена `pricing_version` → пересчёт cost/tier/cf/exp по хранимым полям, без реингеста.
    private func recomputeIfPricingChanged(_ db: GRDB.Database) throws {
        let stored = try AnalyticsMetaRow
            .filter(AnalyticsMetaRow.Columns.key == "pricing_version")
            .fetchOne(db)?.value
        guard stored != pricingVersion else { return }
        if stored != nil {
            for var row in try AnalyticsTurnRow.fetchAll(db) {
                TurnCostCalculator.recompute(&row)
                try row.update(db)
            }
        }
        try AnalyticsMetaRow(key: "pricing_version", value: pricingVersion)
            .insert(db, onConflict: .replace)
    }

    // MARK: - File walk

    private func ingestSource(_ db: GRDB.Database, base: URL, kind: Kind) throws {
        guard FileManager.default.fileExists(atPath: base.path) else { return }
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []
        ) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = values?.contentModificationDate?.timeIntervalSince1970
            let size = values?.fileSize.map(Int64.init)

            // Файловый гейт: mtime/size не изменились — файл пропускаем целиком.
            if let existing = try AnalyticsIngestStateRow
                .filter(AnalyticsIngestStateRow.Columns.path == url.path)
                .fetchOne(db),
               existing.mtime == mtime, existing.size == size {
                continue
            }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            let fallback = url.deletingPathExtension().lastPathComponent

            switch kind {
            case .claude:
                let turns = ClaudeTranscriptParser.parse(lines: lines, sessionFallback: fallback)
                for turn in turns where !turn.ts.isEmpty {
                    try AnalyticsUpserter.upsertTurn(TurnCostCalculator.enrich(turn, timeZone: timeZone), in: db)
                }
            case .codex:
                let (turns, rateLimits) = CodexRolloutParser.parse(lines: lines, sessionFallback: fallback)
                for turn in turns where !turn.ts.isEmpty {
                    try AnalyticsUpserter.upsertTurn(TurnCostCalculator.enrich(turn, timeZone: timeZone), in: db)
                }
                for rl in rateLimits {
                    try AnalyticsUpserter.upsertRateLimit(
                        AnalyticsRateLimitRow(path: url.path, ts: rl.ts, window: rl.window, usedPercent: rl.usedPercent),
                        in: db
                    )
                }
            }

            try AnalyticsIngestStateRow(path: url.path, mtime: mtime, size: size)
                .insert(db, onConflict: .replace)
        }
    }
}
