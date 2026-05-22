import Foundation

protocol Fetcher {
    func fetch(since: Date) async throws -> FetchResult
}

enum FetchResult {
    case aiUsage([AIUsageRow])
    case github([GitHubRow])
}
