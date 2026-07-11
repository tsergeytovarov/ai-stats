import Foundation

protocol Fetcher {
    func fetch(since: Date) async throws -> FetchResult
}

struct CcusagePayload {
    let dayRows: [AIUsageRow]
    let modelRows: [AIUsageModelRow]
}

enum FetchResult {
    case aiUsage(CcusagePayload)
}
