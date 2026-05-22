import Foundation

protocol Fetcher {
    func fetch(since: Date) async throws -> FetchResult
}

struct GitHubFetchPayload {
    let dailyCommits: [GitHubRow]
    let dailyLOC: [GitHubLOCDailyRow]
}

struct CcusagePayload {
    let dayRows: [AIUsageRow]
    let modelRows: [AIUsageModelRow]
}

enum FetchResult {
    case aiUsage(CcusagePayload)
    case github(GitHubFetchPayload)
}
