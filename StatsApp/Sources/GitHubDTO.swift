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
