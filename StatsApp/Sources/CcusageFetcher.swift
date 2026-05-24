import Foundation

enum CcusageParser {
    static func parse(_ data: Data, source: String, now: () -> Date) throws -> CcusagePayload {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: now())
        let encoder = JSONEncoder()

        switch source {
        case "codex":
            let report = try JSONDecoder().decode(CcusageCodexReport.self, from: data)
            var dayRows: [AIUsageRow] = []
            var modelRows: [AIUsageModelRow] = []
            for day in report.daily {
                let modelsJson = (try? String(data: encoder.encode(day.modelNames), encoding: .utf8)) ?? "[]"
                let cost = computeCodexCost(day)
                let reasoningOut = day.models?.values.reduce(0) { $0 + ($1.reasoningOutputTokens ?? 0) } ?? 0
                dayRows.append(AIUsageRow(
                    id: nil,
                    day: day.date,
                    source: source,
                    modelsJson: modelsJson,
                    inputTokens: day.inputTokens + day.cachedInputTokens,
                    inputTokensNoCache: day.inputTokens,
                    outputTokens: day.outputTokens + reasoningOut,
                    costUsd: cost,
                    updatedAt: nowString
                ))
                if let models = day.models {
                    for (name, stats) in models {
                        let reasoningOutModel = stats.reasoningOutputTokens ?? 0
                        let modelCost = PricingTable.cost(
                            model: name,
                            inputTokens: stats.inputTokens,
                            outputTokens: stats.outputTokens + reasoningOutModel,
                            cacheReadTokens: stats.cachedInputTokens ?? 0,
                            cacheCreateTokens: 0
                        )
                        modelRows.append(AIUsageModelRow(
                            id: nil,
                            day: day.date,
                            source: source,
                            model: name,
                            inputTokens: stats.inputTokens + (stats.cachedInputTokens ?? 0),
                            inputTokensNoCache: stats.inputTokens,
                            outputTokens: stats.outputTokens + reasoningOutModel,
                            costUsd: modelCost,
                            updatedAt: nowString
                        ))
                    }
                }
            }
            return CcusagePayload(dayRows: dayRows, modelRows: modelRows)
        default: // claude и любой другой провайдер, который пользуется claude-подобной схемой
            let report = try JSONDecoder().decode(CcusageClaudeReport.self, from: data)
            var dayRows: [AIUsageRow] = []
            var modelRows: [AIUsageModelRow] = []
            for day in report.daily {
                let modelsJson = (try? String(data: encoder.encode(day.modelsUsed), encoding: .utf8)) ?? "[]"
                let cost = computeClaudeCost(day)
                dayRows.append(AIUsageRow(
                    id: nil,
                    day: day.date,
                    source: source,
                    modelsJson: modelsJson,
                    inputTokens: day.inputTokens + day.cacheCreationTokens + day.cacheReadTokens,
                    inputTokensNoCache: day.inputTokens,
                    outputTokens: day.outputTokens,
                    costUsd: cost,
                    updatedAt: nowString
                ))
                if let breakdowns = day.modelBreakdowns {
                    for b in breakdowns {
                        let modelCost = PricingTable.cost(
                            model: b.modelName,
                            inputTokens: b.inputTokens,
                            outputTokens: b.outputTokens,
                            cacheReadTokens: b.cacheReadTokens,
                            cacheCreateTokens: b.cacheCreationTokens
                        )
                        modelRows.append(AIUsageModelRow(
                            id: nil,
                            day: day.date,
                            source: source,
                            model: b.modelName,
                            inputTokens: b.inputTokens + b.cacheCreationTokens + b.cacheReadTokens,
                            inputTokensNoCache: b.inputTokens,
                            outputTokens: b.outputTokens,
                            costUsd: modelCost,
                            updatedAt: nowString
                        ))
                    }
                }
            }
            return CcusagePayload(dayRows: dayRows, modelRows: modelRows)
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
    case invalidCommandPrefix(String)
    case emptyCommandPrefix

    var errorDescription: String? {
        switch self {
        case .processFailed(let code, let stderr):
            return "ccusage exited with code \(code): \(stderr)"
        case .binaryNotFound(let head):
            return "Cannot find executable '\(head)'. Install bun or node, or fix ccusage_command in config."
        case .invalidCommandPrefix(let head):
            return "ccusage_command[0] должен быть 'npx', 'bunx' или абсолютный путь (получено: \"\(head)\"). " +
                   "Это защита от подмены команды через config."
        case .emptyCommandPrefix:
            return "ccusage_command не может быть пустым. Используй [\"npx\", \"-y\", \"ccusage@20\"]."
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
        // Валидируем ПЕРВУЮ команду до запуска Process — это закрывает arbitrary
        // command execution через подмену config.json (см. ниже validateCommandHead).
        guard let head = commandPrefix.first else {
            throw CcusageError.emptyCommandPrefix
        }
        try Self.validateCommandHead(head)

        let process = Process()
        process.executableURL = try resolveExecutable(head)
        process.arguments = args
        // GUI-приложение получает PATH = /usr/bin:/bin без brew/nvm. Child
        // process (npx → node) запустится через shebang `#!/usr/bin/env node`,
        // и `env` ищет node ровно в этом PATH → exit 127. Прокидываем child'у
        // расширенный PATH по тем же дирам что и resolveExecutable.
        process.environment = Self.enrichedEnvironment(base: ProcessInfo.processInfo.environment)

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

        let payload = try CcusageParser.parse(stdoutData, source: provider, now: now)
        return .aiUsage(payload)
    }

    /// Системные дир'ы с node/npx/bun (brew). Раньше включали и `~/.bun/bin`,
    /// но это home-writable — любой процесс с доступом к home может подложить
    /// fake-binary. Bun-юзеры пусть добавляют его в shell PATH (env прокидывается
    /// child'у через enrichedEnvironment, поэтому работать будет).
    static func extraSearchPaths(home: String = NSHomeDirectory()) -> [String] {
        _ = home  // оставили параметр для обратной совместимости тестов
        return ["/opt/homebrew/bin", "/usr/local/bin"]
    }

    /// Разрешённые имена команд для commandPrefix[0]. Всё остальное должно быть
    /// абсолютным путём — иначе reject. Это закрывает возможность подсунуть
    /// `rm` / `curl <attacker>` / etc через config.json.
    static let allowedRelativeCommands: Set<String> = ["npx", "bunx"]

    /// Валидация commandPrefix[0]. См. allowedRelativeCommands.
    static func validateCommandHead(_ head: String) throws {
        if head.hasPrefix("/") {
            // Абсолютный путь — приемлемо. Existence/executability проверит resolveExecutable.
            // Запрещаем `..` в любом виде — никаких relative ascents даже в абсолютных путях.
            guard !head.contains("..") else {
                throw CcusageError.invalidCommandPrefix(head)
            }
            return
        }
        guard Self.allowedRelativeCommands.contains(head) else {
            throw CcusageError.invalidCommandPrefix(head)
        }
    }

    /// Возвращает env с PATH = extras + base.PATH, без дублирующихся директорий.
    /// Pure-функция — тестируется без Process.
    static func enrichedEnvironment(base: [String: String]) -> [String: String] {
        let basePath = base["PATH"] ?? ""
        let baseDirs = basePath.split(separator: ":").map(String.init)
        var seen: Set<String> = []
        var merged: [String] = []
        for dir in extraSearchPaths() + baseDirs where !dir.isEmpty && seen.insert(dir).inserted {
            merged.append(dir)
        }
        var env = base
        env["PATH"] = merged.joined(separator: ":")
        return env
    }

    private func resolveExecutable(_ name: String) throws -> URL {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }

        let candidatePaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            + Self.extraSearchPaths()

        for dir in candidatePaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw CcusageError.binaryNotFound(commandHead: name)
    }
}
