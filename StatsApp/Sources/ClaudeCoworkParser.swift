import Foundation

enum ClaudeCoworkParser {

    static func parse(
        files: [Data],
        since: Date,
        timezone: TimeZone,
        now: () -> Date
    ) throws -> CcusagePayload {
        // Реальные cowork timestamps приходят с дробными секундами ("...T10:00:00.794Z"),
        // но не гарантированно — парсим оба варианта (см. parseTimestamp).
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        let parseTimestamp: (String) -> Date? = { s in
            isoFractional.date(from: s) ?? isoPlain.date(from: s)
        }
        let nowString = isoPlain.string(from: now())

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = timezone
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")

        let sinceDay = dayFormatter.string(from: since)

        var seen = Set<String>()
        var entries: [Entry] = []

        for data in files {
            guard let text = String(data: data, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard
                    let lineData = String(line).data(using: .utf8),
                    let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                    (obj["type"] as? String) == "assistant",
                    let message = obj["message"] as? [String: Any],
                    let msgId = message["id"] as? String,
                    let model = message["model"] as? String,
                    // "<synthetic>" — служебные сообщения Claude Code (compaction и т.п.),
                    // не реальные вызовы модели. В статистику не идут.
                    model != "<synthetic>",
                    let usage = message["usage"] as? [String: Any],
                    let tsString = obj["timestamp"] as? String,
                    let timestamp = parseTimestamp(tsString)
                else { continue }

                guard !seen.contains(msgId) else { continue }
                seen.insert(msgId)

                entries.append(Entry(
                    messageId: msgId,
                    timestamp: timestamp,
                    model: model,
                    inputTokens: Int64(usage["input_tokens"] as? Int ?? 0),
                    cacheCreateTokens: Int64(usage["cache_creation_input_tokens"] as? Int ?? 0),
                    cacheReadTokens: Int64(usage["cache_read_input_tokens"] as? Int ?? 0),
                    outputTokens: Int64(usage["output_tokens"] as? Int ?? 0)
                ))
            }
        }

        let filtered = entries.filter { dayFormatter.string(from: $0.timestamp) >= sinceDay }

        // Aggregate by (day, model)
        var byDayModel: [DayModelKey: Aggregated] = [:]
        for e in filtered {
            let key = DayModelKey(day: dayFormatter.string(from: e.timestamp), model: e.model)
            var agg = byDayModel[key] ?? Aggregated()
            agg.inputTokens       += e.inputTokens + e.cacheCreateTokens + e.cacheReadTokens
            agg.inputTokensNoCache += e.inputTokens
            agg.cacheCreateTokens += e.cacheCreateTokens
            agg.cacheReadTokens   += e.cacheReadTokens
            agg.outputTokens      += e.outputTokens
            byDayModel[key] = agg
        }

        var modelRows: [AIUsageModelRow] = []
        for (key, agg) in byDayModel {
            modelRows.append(AIUsageModelRow(
                id: nil,
                day: key.day,
                source: "claude-cowork",
                model: key.model,
                inputTokens: agg.inputTokens,
                inputTokensNoCache: agg.inputTokensNoCache,
                outputTokens: agg.outputTokens,
                costUsd: PricingTable.cost(
                    model: key.model,
                    inputTokens: agg.inputTokensNoCache,
                    outputTokens: agg.outputTokens,
                    cacheReadTokens: agg.cacheReadTokens,
                    cacheCreateTokens: agg.cacheCreateTokens
                ),
                updatedAt: nowString
            ))
        }

        // Aggregate model rows into day rows
        var byDay: [String: DayAgg] = [:]
        for mr in modelRows {
            var agg = byDay[mr.day] ?? DayAgg()
            agg.inputTokens       += mr.inputTokens
            agg.inputTokensNoCache += mr.inputTokensNoCache
            agg.outputTokens      += mr.outputTokens
            agg.costUsd           += mr.costUsd
            agg.models.insert(mr.model)
            byDay[mr.day] = agg
        }

        let encoder = JSONEncoder()
        var dayRows: [AIUsageRow] = []
        for (day, agg) in byDay {
            let sortedModels = agg.models.sorted()
            let modelsJson = (try? String(data: encoder.encode(sortedModels), encoding: .utf8)) ?? "[]"
            dayRows.append(AIUsageRow(
                id: nil,
                day: day,
                source: "claude-cowork",
                modelsJson: modelsJson,
                inputTokens: agg.inputTokens,
                inputTokensNoCache: agg.inputTokensNoCache,
                outputTokens: agg.outputTokens,
                costUsd: agg.costUsd,
                updatedAt: nowString
            ))
        }

        return CcusagePayload(dayRows: dayRows, modelRows: modelRows)
    }

    // MARK: - Private

    private struct Entry {
        let messageId: String
        let timestamp: Date
        let model: String
        let inputTokens: Int64
        let cacheCreateTokens: Int64
        let cacheReadTokens: Int64
        let outputTokens: Int64
    }

    private struct DayModelKey: Hashable {
        let day: String
        let model: String
    }

    private struct Aggregated {
        var inputTokens: Int64 = 0
        var inputTokensNoCache: Int64 = 0
        var cacheCreateTokens: Int64 = 0
        var cacheReadTokens: Int64 = 0
        var outputTokens: Int64 = 0
    }

    private struct DayAgg {
        var inputTokens: Int64 = 0
        var inputTokensNoCache: Int64 = 0
        var outputTokens: Int64 = 0
        var costUsd: Double = 0
        var models: Set<String> = []
    }
}
