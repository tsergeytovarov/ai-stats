import Foundation

struct ClaudeCoworkFetcher: Fetcher {

    let sessionsBaseURL: URL
    let timezone: TimeZone
    let now: () -> Date

    init(timezone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.sessionsBaseURL = appSupport
            .appendingPathComponent("Claude/local-agent-mode-sessions")
        self.timezone = timezone
        self.now = now
    }

    init(sessionsBaseURL: URL, timezone: TimeZone = .current, now: @escaping () -> Date = Date.init) {
        self.sessionsBaseURL = sessionsBaseURL
        self.timezone = timezone
        self.now = now
    }

    func fetch(since: Date) async throws -> FetchResult {
        let files = collectJsonlFiles()
        let datas = files.compactMap { try? Data(contentsOf: $0) }
        let payload = try ClaudeCoworkParser.parse(
            files: datas, since: since, timezone: timezone, now: now
        )
        return .aiUsage(payload)
    }

    // Enumerates all *.jsonl that are inside a `.claude/projects/` subtree
    // under sessionsBaseURL. Hidden dirs are included intentionally — .claude is one.
    private func collectJsonlFiles() -> [URL] {
        guard FileManager.default.fileExists(atPath: sessionsBaseURL.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsBaseURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let components = url.pathComponents
            // Only pick up jsonl files that sit inside .claude/projects/
            guard let dotClaudeIdx = components.lastIndex(of: ".claude"),
                  dotClaudeIdx + 1 < components.count,
                  components[dotClaudeIdx + 1] == "projects"
            else { continue }
            results.append(url)
        }
        return results
    }
}
