import Foundation

/// Живые лимиты Codex через `codex app-server`: JSON-RPC по stdin/stdout,
/// initialize → initialized → account/rateLimits/read. Если бинаря нет или RPC
/// молчит — последний снапшот из свежих rollout-логов.
final class CodexLimitsFetcher: LimitsFetching {
    let provider: LimitProvider = .codex

    private let sessionsDir: URL
    private let rpcTimeout: TimeInterval
    private let now: @Sendable () -> Date

    init(sessionsDir: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".codex/sessions"),
         rpcTimeout: TimeInterval = 12,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.sessionsDir = sessionsDir
        self.rpcTimeout = rpcTimeout
        self.now = now
    }

    func fetch() async -> ProviderLimits {
        if let windows = rpcWindows(), !windows.isEmpty {
            return ProviderLimits(provider: .codex, windows: windows, status: .ok,
                                  fetchedAt: now(), error: nil)
        }
        if let windows = rolloutWindows(), !windows.isEmpty {
            // Данные из лога могут отставать — честно помечаем как несвежие.
            return ProviderLimits(provider: .codex, windows: windows, status: .stale,
                                  fetchedAt: now(), error: nil)
        }
        return .failure(.codex, status: .unavailable, error: "codex недоступен")
    }

    // MARK: - RPC

    private func rpcWindows() -> [LimitWindow]? {
        guard let executable = Self.locateCodex() else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        defer {
            process.terminate()
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }

        func send(_ object: [String: Any]) {
            guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
            data.append(0x0A)
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }

        send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": ["clientInfo": ["name": "burn", "version": "1.0.0"]]])

        // Ответы построчные. Читаем до дедлайна: сперва ответ на initialize,
        // потом — на запрос лимитов. Пайп тут безопасен: трафик крошечный.
        let deadline = Date().addingTimeInterval(rpcTimeout)
        var buffer = Data()
        var initialized = false
        while Date() < deadline {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { continue }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<nl]
                buffer = buffer[buffer.index(after: nl)...]
                guard let object = (try? JSONSerialization.jsonObject(with: Data(lineData)))
                        as? [String: Any] else { continue }
                let id = (object["id"] as? NSNumber)?.intValue
                if id == 1, object["result"] != nil, !initialized {
                    initialized = true
                    send(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
                    send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read",
                          "params": [:]])
                } else if id == 2 {
                    return CodexLimitsParser.parseRPC(Data(lineData))
                }
            }
        }
        return nil
    }

    /// Ищем codex в системных дир'ах и в ~/.local/bin.
    ///
    /// Домашний путь тут включён сознательно, в отличие от
    /// CcusageFetcher.extraSearchPaths: ~/.local/bin — штатное место официального
    /// установщика codex, и без него живой RPC оказывается мёртвым кодом почти
    /// у всех. Размен принят явно: тот, кто может писать в домашнюю папку,
    /// уже правит shell-профиль и конфиги агентов, так что подложенный сюда
    /// бинарь не расширяет его возможности.
    static func locateCodex(fileManager: FileManager = .default,
                            home: String = NSHomeDirectory()) -> URL? {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex",
                          "\(home)/.local/bin/codex"]
        return candidates.map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Фолбэк на rollout-логи

    private func rolloutWindows() -> [LimitWindow]? {
        let fm = FileManager.default
        guard let files = try? recentRolloutFiles(fm: fm) else { return nil }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            // Снапшот аккаунт-глобальный: берём последний в файле.
            var last: [LimitWindow]?
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if let windows = CodexLimitsParser.parseRolloutLine(String(line)) { last = windows }
            }
            if let last { return last }
        }
        return nil
    }

    private func recentRolloutFiles(fm: FileManager) throws -> [URL] {
        guard let walker = fm.enumerator(at: sessionsDir,
                                         includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        var found: [(Date, URL)] = []
        for case let url as URL in walker where url.lastPathComponent.hasPrefix("rollout-")
            && url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            found.append((date, url))
        }
        return found.sorted { $0.0 > $1.0 }.prefix(30).map(\.1)
    }
}
