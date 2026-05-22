import Foundation

enum CcusageParser {
    static func parse(_ data: Data, source: String, now: () -> Date) throws -> [AIUsageRow] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: now())
        let encoder = JSONEncoder()

        switch source {
        case "codex":
            let report = try JSONDecoder().decode(CcusageCodexReport.self, from: data)
            return report.daily.map { day in
                let modelsJson = (try? String(data: encoder.encode(day.modelNames), encoding: .utf8)) ?? "[]"
                let cost = computeCodexCost(day)
                let reasoningOut = day.models?.values.reduce(0) { $0 + ($1.reasoningOutputTokens ?? 0) } ?? 0
                return AIUsageRow(
                    id: nil,
                    day: day.date,
                    source: source,
                    modelsJson: modelsJson,
                    inputTokens: day.inputTokens + day.cachedInputTokens,
                    outputTokens: day.outputTokens + reasoningOut,
                    costUsd: cost,
                    updatedAt: nowString
                )
            }
        default: // claude и любой другой провайдер, который пользуется claude-подобной схемой
            let report = try JSONDecoder().decode(CcusageClaudeReport.self, from: data)
            return report.daily.map { day in
                let modelsJson = (try? String(data: encoder.encode(day.modelsUsed), encoding: .utf8)) ?? "[]"
                let cost = computeClaudeCost(day)
                return AIUsageRow(
                    id: nil,
                    day: day.date,
                    source: source,
                    modelsJson: modelsJson,
                    inputTokens: day.inputTokens + day.cacheCreationTokens + day.cacheReadTokens,
                    outputTokens: day.outputTokens,
                    costUsd: cost,
                    updatedAt: nowString
                )
            }
        }
    }

    private static func computeClaudeCost(_ day: CcusageClaudeDay) -> Double {
        // Если breakdown есть — суммируем точно по модели.
        if let breakdowns = day.modelBreakdowns, !breakdowns.isEmpty {
            return breakdowns.reduce(0) { acc, b in
                acc + PricingTable.cost(
                    model: b.modelName,
                    inputTokens: b.inputTokens,
                    outputTokens: b.outputTokens,
                    cacheReadTokens: b.cacheReadTokens,
                    cacheCreateTokens: b.cacheCreationTokens
                )
            }
        }
        // Fallback — берём первую модель из списка modelsUsed и применяем её ставку к агрегату.
        let model = day.modelsUsed.first ?? ""
        return PricingTable.cost(
            model: model,
            inputTokens: day.inputTokens,
            outputTokens: day.outputTokens,
            cacheReadTokens: day.cacheReadTokens,
            cacheCreateTokens: day.cacheCreationTokens
        )
    }

    private static func computeCodexCost(_ day: CcusageCodexDay) -> Double {
        guard let models = day.models, !models.isEmpty else {
            // Нет breakdown — единственный вариант, ставим 0.
            return 0
        }
        return models.reduce(0.0) { acc, kv in
            let (name, stats) = kv
            let reasoningOut = stats.reasoningOutputTokens ?? 0
            return acc + PricingTable.cost(
                model: name,
                inputTokens: stats.inputTokens,
                outputTokens: stats.outputTokens + reasoningOut,
                cacheReadTokens: stats.cachedInputTokens ?? 0,
                cacheCreateTokens: 0
            )
        }
    }
}

enum CcusageError: Error, LocalizedError {
    case processFailed(exitCode: Int32, stderr: String)
    case binaryNotFound(commandHead: String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let code, let stderr):
            return "ccusage exited with code \(code): \(stderr)"
        case .binaryNotFound(let head):
            return "Cannot find executable '\(head)'. Install bun or node, or fix ccusage_command in config."
        }
    }
}

struct CcusageFetcher: Fetcher {
    let commandPrefix: [String]
    let provider: String
    let now: () -> Date

    init(commandPrefix: [String], provider: String, now: @escaping () -> Date = Date.init) {
        self.commandPrefix = commandPrefix
        self.provider = provider
        self.now = now
    }

    func fetch(since: Date) async throws -> FetchResult {
        let sinceArg = DateUtils.isoDayCompact(since)
        let args = Array(commandPrefix.dropFirst()) + [
            provider, "daily", "--json",
            "--since", sinceArg,
            "--timezone", TimeZone.current.identifier,
        ]
        let head = commandPrefix.first ?? "npx"

        let process = Process()
        process.executableURL = try resolveExecutable(head)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw CcusageError.processFailed(exitCode: process.terminationStatus, stderr: stderr)
        }

        let rows = try CcusageParser.parse(stdoutData, source: provider, now: now)
        return .aiUsage(rows)
    }

    private func resolveExecutable(_ name: String) throws -> URL {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }

        let candidatePaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.bun/bin"]

        for dir in candidatePaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw CcusageError.binaryNotFound(commandHead: name)
    }
}
