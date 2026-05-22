import Foundation

struct GitHubResponse: Decodable {
    let data: DataNode?
    let errors: [GraphQLError]?

    struct DataNode: Decodable {
        let viewer: Viewer
    }

    struct Viewer: Decodable {
        let contributionsCollection: ContributionsCollection
    }

    struct ContributionsCollection: Decodable {
        let commitContributionsByRepository: [RepoContribution]
    }

    struct RepoContribution: Decodable {
        let repository: Repository
        let contributions: Contributions
    }

    struct Repository: Decodable {
        let nameWithOwner: String
    }

    struct Contributions: Decodable {
        let nodes: [Node]
    }

    struct Node: Decodable {
        let occurredAt: String
        let commitCount: Int64
    }

    struct GraphQLError: Decodable {
        let message: String
    }
}

struct GitHubContributorStats: Decodable {
    let author: Author?
    let weeks: [Week]

    struct Author: Decodable {
        let login: String
    }

    struct Week: Decodable {
        let w: Int64  // unix seconds (Sunday 00:00 UTC)
        let a: Int64  // additions
        let d: Int64  // deletions
        let c: Int64  // commits
    }
}
