import Foundation

enum GitHubError: Error, LocalizedError {
    case graphqlErrors([String])
    case httpStatus(Int, body: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .graphqlErrors(let msgs): return "GitHub GraphQL errors: \(msgs.joined(separator: "; "))"
        case .httpStatus(let code, let body): return "GitHub HTTP \(code): \(body.prefix(200))"
        case .decoding(let err): return "GitHub decoding: \(err)"
        }
    }
}

enum GitHubResponseParser {
    static func parse(_ data: Data, now: () -> Date) throws -> [GitHubRow] {
        let response: GitHubResponse
        do { response = try JSONDecoder().decode(GitHubResponse.self, from: data) }
        catch { throw GitHubError.decoding(error) }

        if let errors = response.errors, !errors.isEmpty {
            throw GitHubError.graphqlErrors(errors.map(\.message))
        }
        guard let viewer = response.data?.viewer else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: now())

        var rows: [GitHubRow] = []
        for repoNode in viewer.contributionsCollection.commitContributionsByRepository {
            for node in repoNode.contributions.nodes where node.commitCount > 0 {
                let day = String(node.occurredAt.prefix(10))
                rows.append(GitHubRow(
                    id: nil,
                    day: day,
                    repo: repoNode.repository.nameWithOwner,
                    commits: node.commitCount,
                    updatedAt: nowString
                ))
            }
        }
        return rows
    }

    /// Парсит ответ /repos/.../stats/contributors, фильтрует по логину, возвращает LOC-строки.
    static func parseLOCStats(
        _ data: Data,
        repo: String,
        login: String,
        now: () -> Date
    ) throws -> [GitHubLOCWeeklyRow] {
        let allStats: [GitHubContributorStats]
        do { allStats = try JSONDecoder().decode([GitHubContributorStats].self, from: data) }
        catch { throw GitHubError.decoding(error) }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let nowString = isoFormatter.string(from: now())

        guard let mine = allStats.first(where: { $0.author?.login.lowercased() == login.lowercased() }) else {
            return []
        }

        var rows: [GitHubLOCWeeklyRow] = []
        for week in mine.weeks where week.a > 0 || week.d > 0 {
            let sunday = Date(timeIntervalSince1970: Double(week.w))
            let weekStart = DateUtils.isoDay(sunday)
            rows.append(GitHubLOCWeeklyRow(
                id: nil,
                weekStart: weekStart,
                repo: repo,
                additions: week.a,
                deletions: week.d,
                updatedAt: nowString
            ))
        }
        return rows
    }
}

struct GitHubFetcher: Fetcher {
    let token: String
    let login: String
    let session: URLSession
    let now: () -> Date

    init(token: String, login: String, session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.token = token
        self.login = login
        self.session = session
        self.now = now
    }

    func fetch(since: Date) async throws -> FetchResult {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let from = isoFormatter.string(from: since)
        let to = isoFormatter.string(from: now())

        let query = """
        query($from: DateTime!, $to: DateTime!) {
          viewer {
            contributionsCollection(from: $from, to: $to) {
              commitContributionsByRepository(maxRepositories: 100) {
                repository { nameWithOwner }
                contributions(first: 100) {
                  nodes { occurredAt commitCount }
                }
              }
            }
          }
        }
        """

        let body: [String: Any] = ["query": query, "variables": ["from": from, "to": to]]
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ai-stats/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.httpStatus(-1, body: "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.httpStatus(http.statusCode, body: bodyStr)
        }
        let commitRows = try GitHubResponseParser.parse(data, now: now)

        // Collect unique repos from commit response
        let repos = Array(Set(commitRows.map(\.repo)))
        let locRows = await fetchLOCForRepos(repos)

        return .github(GitHubFetchPayload(dailyCommits: commitRows, weeklyLOC: locRows))
    }

    // Fetches LOC stats for all repos, up to 5 concurrently. Skips repos that stay at 202.
    private func fetchLOCForRepos(_ repos: [String]) async -> [GitHubLOCWeeklyRow] {
        var allRows: [GitHubLOCWeeklyRow] = []
        // Process in batches of 5 to limit concurrency
        let batchSize = 5
        var index = 0
        while index < repos.count {
            let batch = Array(repos[index..<min(index + batchSize, repos.count)])
            let batchResults = await withTaskGroup(of: [GitHubLOCWeeklyRow].self) { group in
                for repo in batch {
                    group.addTask {
                        do {
                            return try await self.fetchLOCForRepo(repo)
                        } catch {
                            NSLog("ai-stats LOC fetch error [\(repo)]: \(error)")
                            return []
                        }
                    }
                }
                var results: [GitHubLOCWeeklyRow] = []
                for await rows in group { results.append(contentsOf: rows) }
                return results
            }
            allRows.append(contentsOf: batchResults)
            index += batchSize
        }
        return allRows
    }

    private func fetchLOCForRepo(_ repo: String) async throws -> [GitHubLOCWeeklyRow] {
        let url = URL(string: "https://api.github.com/repos/\(repo)/stats/contributors")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ai-stats/0.1", forHTTPHeaderField: "User-Agent")

        let maxRetries = 3
        for attempt in 0..<maxRetries {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubError.httpStatus(-1, body: "no http response")
            }
            if http.statusCode == 202 {
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                    continue
                } else {
                    NSLog("ai-stats LOC stats still 202 after retries for \(repo), skipping")
                    return []
                }
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                throw GitHubError.httpStatus(http.statusCode, body: bodyStr)
            }
            return try GitHubResponseParser.parseLOCStats(data, repo: repo, login: login, now: now)
        }
        return []
    }
}
