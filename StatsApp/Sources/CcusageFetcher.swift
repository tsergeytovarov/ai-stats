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
                // Trust ccusage costUSD на day-уровне. Fallback (старый ccusage без
                // поля) — сумма по PricingTable, чтобы не потерять данные.
                let cost = day.costUSD ?? computeCodexCost(day)
                let reasoningOut = day.models?.values.reduce(0) { $0 + ($1.reasoningOutputTokens ?? 0) } ?? 0
                dayRows.append(AIUsageRow(
                    id: nil,
                    day: day.date,
                    source: source,
                    modelsJson: modelsJson,
                    inputTokens: day.inputTokens + (day.cacheReadTokens ?? 0) + (day.cacheCreationTokens ?? 0),
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
                            cacheReadTokens: stats.cacheReadTokens ?? 0,
                            cacheCreateTokens: stats.cacheCreationTokens ?? 0
                        )
                        modelRows.append(AIUsageModelRow(
                            id: nil,
                            day: day.date,
                            source: source,
                            model: name,
                            inputTokens: stats.inputTokens + (stats.cacheReadTokens ?? 0) + (stats.cacheCreationTokens ?? 0),
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
                // Trust ccusage cost — он держит up-to-date прайс Anthropic, в т.ч.
                // для новых моделей (claude-opus-4-8 и далее), которые наш PricingTable
                // может не знать. Fallback — PricingTable-сумма для старых ccusage без
                // полей cost/totalCost.
                let cost = day.totalCost ?? computeClaudePricingTableCost(day)
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
                        let modelCost = b.cost ?? PricingTable.cost(
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

    /// Fallback day-level cost для случая, когда ccusage не отдал totalCost (старая
    /// версия). Используется ТОЛЬКО как defensive fallback — модель может быть
    /// неизвестна PricingTable (тогда вернёт 0).
    private static func computeClaudePricingTableCost(_ day: CcusageClaudeDay) -> Double {
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
                cacheReadTokens: stats.cacheReadTokens ?? 0,
                cacheCreateTokens: stats.cacheCreationTokens ?? 0
            )
        }
    }
}

enum CcusageError: Error, LocalizedError {
    case processFailed(exitCode: Int32, stderr: String)
    case binaryNotFound(commandHead: String)
    case invalidCommandPrefix(String)
    case emptyCommandPrefix
    case timedOut(seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "ccusage не ответил за \(Int(seconds)) с и был убит."
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

/// Результат запуска ccusage-процесса: вывод и код возврата.
struct CcusageProcessOutput {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
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

        let output = try Self.runProcess(
            executable: try resolveExecutable(head),
            arguments: args,
            // GUI-приложение получает PATH = /usr/bin:/bin без brew/nvm. Child
            // process (npx → node) запустится через shebang `#!/usr/bin/env node`,
            // и `env` ищет node ровно в этом PATH → exit 127. Прокидываем child'у
            // расширенный PATH по тем же дирам что и resolveExecutable.
            environment: Self.enrichedEnvironment(base: ProcessInfo.processInfo.environment)
        )

        guard output.exitCode == 0 else {
            let stderr = String(data: output.stderr, encoding: .utf8) ?? ""
            throw CcusageError.processFailed(exitCode: output.exitCode, stderr: stderr)
        }

        let payload = try CcusageParser.parse(output.stdout, source: provider, now: now)
        return .aiUsage(payload)
    }

    /// Сколько ждём ccusage, прежде чем считать его зависшим. Реальный прогон
    /// укладывается в единицы секунд даже на годовом окне.
    static let processTimeout: TimeInterval = 120

    /// Запускает процесс и собирает его вывод.
    ///
    /// Вывод идёт во временные файлы, а не в пайпы. Пайп держит всего 16 КБ:
    /// когда ccusage писал больше, он навсегда блокировался в write(), а мы —
    /// в waitUntilExit(), потому что читали пайпы уже после выхода процесса.
    /// Синк вставал намертво и молча: source оставался inFlight, ошибки в лог
    /// не попадало, цифры расходов просто замирали. Файл не блокируется никогда.
    static func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval = processTimeout
    ) throws -> CcusageProcessOutput {
        let fm = FileManager.default
        let stem = fm.temporaryDirectory.appendingPathComponent("ccusage-\(UUID().uuidString)")
        let stdoutURL = stem.appendingPathExtension("out")
        let stderrURL = stem.appendingPathExtension("err")
        fm.createFile(atPath: stdoutURL.path, contents: nil)
        fm.createFile(atPath: stderrURL.path, contents: nil)
        defer {
            try? fm.removeItem(at: stdoutURL)
            try? fm.removeItem(at: stderrURL)
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        // Пустой stdin: npm/npx умеет спросить подтверждение и ждать ответа,
        // которого у menu-bar-приложения нет. С /dev/null он сразу получит EOF.
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            Self.kill(process)
            throw CcusageError.timedOut(seconds: timeout)
        }

        return CcusageProcessOutput(
            stdout: (try? Data(contentsOf: stdoutURL)) ?? Data(),
            stderr: (try? Data(contentsOf: stderrURL)) ?? Data(),
            exitCode: process.terminationStatus
        )
    }

    /// SIGTERM, а если процесс не ушёл за grace-период — SIGKILL. Зависший в
    /// write() npm на TERM реагирует не всегда.
    private static func kill(_ process: Process, grace: TimeInterval = 2) {
        process.terminate()
        let deadline = Date().addingTimeInterval(grace)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
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
