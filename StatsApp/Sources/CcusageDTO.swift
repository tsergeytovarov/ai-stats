import Foundation

struct CcusageReport: Decodable {
    let type: String
    let data: [CcusageDay]
}

struct CcusageDay: Decodable {
    let date: String
    let models: [String]
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheCreationTokens: Int64
    let cacheReadTokens: Int64
    let totalTokens: Int64
    let costUSD: Double
}
