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

struct ViewerIDResponse: Decodable {
    let data: DataNode?
    let errors: [GitHubResponse.GraphQLError]?
    struct DataNode: Decodable { let viewer: Viewer }
    struct Viewer: Decodable { let id: String }
}

struct CommitHistoryResponse: Decodable {
    let data: DataNode?
    let errors: [GitHubResponse.GraphQLError]?
    struct DataNode: Decodable { let repository: Repository? }
    struct Repository: Decodable { let defaultBranchRef: BranchRef? }
    struct BranchRef: Decodable { let target: CommitTarget? }
    struct CommitTarget: Decodable { let history: History? }
    struct History: Decodable {
        let pageInfo: PageInfo
        let nodes: [Node]
    }
    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }
    struct Node: Decodable {
        let committedDate: String
        let additions: Int64
        let deletions: Int64
    }
}
