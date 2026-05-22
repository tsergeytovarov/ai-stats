import Foundation

protocol Fetcher {
    func fetch(since: Date) async throws -> FetchResult
}

struct GitHubFetchPayload {
    let dailyCommits: [GitHubRow]
    let weeklyLOC: [GitHubLOCWeeklyRow]
}

enum FetchResult {
    case aiUsage([AIUsageRow])
    case github(GitHubFetchPayload)
}
