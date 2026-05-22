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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubError.httpStatus(http.statusCode, body: body)
        }
        let rows = try GitHubResponseParser.parse(data, now: now)
        return .github(rows)
    }
}
