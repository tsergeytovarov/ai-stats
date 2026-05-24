import Foundation
import os.log

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

    /// Агрегирует nodes истории коммитов по дням.
    static func aggregateCommitsByDay(_ nodes: [CommitHistoryResponse.Node]) -> [(day: String, add: Int64, del: Int64)] {
        var perDay: [String: (add: Int64, del: Int64)] = [:]
        for node in nodes {
            let day = String(node.committedDate.prefix(10))
            var t = perDay[day] ?? (0, 0)
            t.add += node.additions
            t.del += node.deletions
            perDay[day] = t
        }
        return perDay.map { (day: $0.key, add: $0.value.add, del: $0.value.del) }
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
        let commitRows = try await fetchCommits(since: since)
        let viewerId = try await fetchViewerID()
        let repos = Array(Set(commitRows.map(\.repo)))
        let locRows = await fetchLOCForRepos(repos, viewerId: viewerId, since: since)
        return .github(GitHubFetchPayload(dailyCommits: commitRows, dailyLOC: locRows))
    }

    // MARK: - Commits (existing contributionsCollection GraphQL)

    private func fetchCommits(since: Date) async throws -> [GitHubRow] {
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

        let data = try await graphqlPost(query: query, variables: ["from": from, "to": to])
        return try GitHubResponseParser.parse(data, now: now)
    }

    // MARK: - Viewer ID

    private func fetchViewerID() async throws -> String {
        let query = "query { viewer { id } }"
        let data = try await graphqlPost(query: query, variables: [:])
        let decoded: ViewerIDResponse
        do { decoded = try JSONDecoder().decode(ViewerIDResponse.self, from: data) }
        catch { throw GitHubError.decoding(error) }
        if let errs = decoded.errors, !errs.isEmpty {
            throw GitHubError.graphqlErrors(errs.map(\.message))
        }
        guard let id = decoded.data?.viewer.id else {
            throw GitHubError.httpStatus(-1, body: "no viewer id")
        }
        return id
    }

    // MARK: - LOC via commit history

    private func fetchLOCForRepos(_ repos: [String], viewerId: String, since: Date) async -> [GitHubLOCDailyRow] {
        var all: [GitHubLOCDailyRow] = []
        let batchSize = 5
        var idx = 0
        while idx < repos.count {
            let batch = Array(repos[idx..<min(idx + batchSize, repos.count)])
            let batchResults = await withTaskGroup(of: [GitHubLOCDailyRow].self) { group in
                for repo in batch {
                    group.addTask {
                        do {
                            return try await self.fetchLOCForRepo(repo, viewerId: viewerId, since: since)
                        } catch {
                            // repo nameWithOwner может раскрыть private репы — .private.
                            // error содержит response body (см. GitHubError.httpStatus) — .private.
                            AppLogger.github.error(
                                "LOC fetch failed [\(repo, privacy: .private)]: \(error.localizedDescription, privacy: .private)"
                            )
                            return []
                        }
                    }
                }
                var results: [GitHubLOCDailyRow] = []
                for await r in group { results.append(contentsOf: r) }
                return results
            }
            all.append(contentsOf: batchResults)
            idx += batchSize
        }
        return all
    }

    private func fetchLOCForRepo(_ repo: String, viewerId: String, since: Date) async throws -> [GitHubLOCDailyRow] {
        let parts = repo.split(separator: "/")
        guard parts.count == 2 else { return [] }
        let owner = String(parts[0])
        let name = String(parts[1])

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let sinceStr = isoFormatter.string(from: since)
        let nowString = isoFormatter.string(from: now())

        let query = """
        query($owner: String!, $name: String!, $author: ID!, $since: GitTimestamp!, $cursor: String) {
          repository(owner: $owner, name: $name) {
            defaultBranchRef {
              target {
                ... on Commit {
                  history(first: 100, author: { id: $author }, since: $since, after: $cursor) {
                    pageInfo { hasNextPage endCursor }
                    nodes { committedDate additions deletions }
                  }
                }
              }
            }
          }
        }
        """

        var cursor: String? = nil
        var allNodes: [CommitHistoryResponse.Node] = []

        repeat {
            var vars: [String: Any] = [
                "owner": owner, "name": name, "author": viewerId, "since": sinceStr
            ]
            if let c = cursor { vars["cursor"] = c }

            let data = try await graphqlPost(query: query, variables: vars)
            let decoded: CommitHistoryResponse
            do { decoded = try JSONDecoder().decode(CommitHistoryResponse.self, from: data) }
            catch { throw GitHubError.decoding(error) }

            if let errs = decoded.errors, !errs.isEmpty {
                // 404 / deleted repo etc — skip silently. error messages могут содержать
                // имена приватных репов / другую meta → .private.
                let joined = errs.map(\.message).joined(separator: "; ")
                AppLogger.github.warning(
                    "LOC graphql errors [\(repo, privacy: .private)]: \(joined, privacy: .private)"
                )
                return []
            }
            guard let history = decoded.data?.repository?.defaultBranchRef?.target?.history else {
                return []  // no default branch or no history
            }
            allNodes.append(contentsOf: history.nodes)
            cursor = history.pageInfo.hasNextPage ? history.pageInfo.endCursor : nil
        } while cursor != nil

        return GitHubResponseParser.aggregateCommitsByDay(allNodes).map { day, add, del in
            GitHubLOCDailyRow(id: nil, day: day, repo: repo, additions: add, deletions: del, updatedAt: nowString)
        }
    }

    // MARK: - HTTP

    private func graphqlPost(query: String, variables: [String: Any]) async throws -> Data {
        let body: [String: Any] = ["query": query, "variables": variables]
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
        return data
    }
}
