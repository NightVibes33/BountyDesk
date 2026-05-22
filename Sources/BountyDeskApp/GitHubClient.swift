import Foundation

struct GitHubClient {
    var baseURL = URL(string: "https://api.github.com")!
    var session: URLSession = .shared

    func validateToken(_ token: String) async throws -> GitHubUser {
        try await request("/user", token: token)
    }

    func searchClaimPullRequests(username: String, token: String) async throws -> [GitHubSearchItem] {
        let queries = [
            "author:\(username) is:pr /claim in:body,comments",
            "author:\(username) is:pr \"@algora-pbc\" in:body,comments",
            "author:\(username) is:pr algora in:title,body,comments",
            "author:\(username) is:pr bounty in:title,body,comments",
            "author:\(username) is:pr commenter:algora-pbc",
            "author:\(username) is:pr label:\"🙋 Bounty claim\""
        ]
        return try await searchPullRequests(queries: queries, token: token, perPage: 75)
    }

    func searchRecentAuthoredPullRequests(username: String, token: String) async throws -> [GitHubSearchItem] {
        let queries = [
            "author:\(username) is:pr state:open",
            "author:\(username) is:pr state:closed"
        ]
        return try await searchPullRequests(queries: queries, token: token, perPage: 100)
    }

    private func searchPullRequests(queries: [String], token: String, perPage: Int) async throws -> [GitHubSearchItem] {
        var seen = Set<String>()
        var items: [GitHubSearchItem] = []
        var firstError: Error?
        for query in queries {
            let response: GitHubSearchResponse
            do {
                response = try await searchIssues(query: query, token: token, perPage: perPage)
            } catch {
                if firstError == nil { firstError = error }
                continue
            }
            for item in response.items where item.pullRequest != nil && seen.insert(item.htmlUrl).inserted {
                items.append(item)
            }
        }
        if items.isEmpty, let firstError {
            throw firstError
        }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    func searchOpenBountyIssues(token: String?, org: String? = nil, repo: String? = nil, language: String? = nil, perPage: Int = 50) async throws -> [GitHubSearchItem] {
        var qualifiers = "is:issue state:open"
        if let org, org.isEmpty == false { qualifiers += " org:\(org)" }
        if let repo, repo.isEmpty == false { qualifiers += " repo:\(repo)" }
        if let language, language.isEmpty == false { qualifiers += " language:\(language)" }
        let queries = [
            "\(qualifiers) label:\"💎 Bounty\"",
            "\(qualifiers) label:bounty algora",
            "\(qualifiers) \"Total prize pool\"",
            "\(qualifiers) /bounty",
            "\(qualifiers) algora bounty"
        ]
        var seen = Set<String>()
        var items: [GitHubSearchItem] = []
        for query in queries {
            let response = try await searchIssues(query: query, token: token, perPage: perPage)
            for item in response.items where item.pullRequest == nil && seen.insert(item.htmlUrl).inserted {
                items.append(item)
            }
        }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    func searchCompetitorPullRequests(owner: String, repo: String, issueNumber: Int, token: String?) async throws -> [GitHubSearchItem] {
        let query = "repo:\(owner)/\(repo) type:pr #\(issueNumber)"
        return try await searchIssues(query: query, token: token, perPage: 50).items.filter { $0.pullRequest != nil }
    }

    func pullRequest(owner: String, repo: String, number: Int, token: String?) async throws -> GitHubPullRequestResponse {
        try await request("/repos/\(owner)/\(repo)/pulls/\(number)", token: token)
    }

    func issue(owner: String, repo: String, number: Int, token: String?) async throws -> GitHubIssueResponse {
        try await request("/repos/\(owner)/\(repo)/issues/\(number)", token: token)
    }

    func issueComments(owner: String, repo: String, number: Int, token: String?) async throws -> [GitHubComment] {
        try await request("/repos/\(owner)/\(repo)/issues/\(number)/comments?per_page=100", token: token)
    }

    func pullRequestComments(owner: String, repo: String, number: Int, token: String?) async throws -> [GitHubComment] {
        try await request("/repos/\(owner)/\(repo)/pulls/\(number)/comments?per_page=100", token: token)
    }

    func repository(owner: String, repo: String, token: String?) async throws -> GitHubRepositoryResponse {
        try await request("/repos/\(owner)/\(repo)", token: token)
    }

    func checkRuns(owner: String, repo: String, ref: String, token: String?) async throws -> GitHubCheckRunsResponse {
        try await request("/repos/\(owner)/\(repo)/commits/\(ref)/check-runs?per_page=100", token: token, accept: "application/vnd.github+json")
    }

    func combinedStatus(owner: String, repo: String, ref: String, token: String?) async throws -> GitHubCombinedStatusResponse {
        try await request("/repos/\(owner)/\(repo)/commits/\(ref)/status", token: token)
    }

    func repositoryFile(owner: String, repo: String, path: String, token: String?) async -> String? {
        do {
            let file: GitHubContentFile = try await request("/repos/\(owner)/\(repo)/contents/\(path)", token: token)
            guard file.type == "file", let encoded = file.content else { return nil }
            let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
            guard let data = Data(base64Encoded: cleaned) else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func searchIssues(query: String, token: String?, perPage: Int) async throws -> GitHubSearchResponse {
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "order", value: "desc"),
            URLQueryItem(name: "per_page", value: "\(perPage)")
        ]
        guard let url = components.url else { throw GitHubAPIError.invalidURL }
        return try await request(url: url, token: token, accept: "application/vnd.github.text-match+json")
    }

    func request<T: Decodable>(_ endpoint: String, token: String?, accept: String = "application/vnd.github+json") async throws -> T {
        guard let url = URL(string: endpoint, relativeTo: baseURL) else { throw GitHubAPIError.invalidURL }
        return try await request(url: url, token: token, accept: accept)
    }

    func request<T: Decodable>(url: URL, token: String?, accept: String = "application/vnd.github+json") async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("BountyDesk/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder.github.decode(GitHubErrorMessage.self, from: data).message) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw GitHubAPIError.httpStatus(http.statusCode, message)
        }
        return try JSONDecoder.github.decode(T.self, from: data)
    }

    static func repositorySlug(from repositoryURL: String) -> (owner: String, repo: String)? {
        guard let url = URL(string: repositoryURL) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[0] == "repos" else { return nil }
        return (parts[1], parts[2])
    }
}

enum GitHubAPIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid GitHub URL."
        case .invalidResponse: return "GitHub returned an invalid response."
        case .httpStatus(let code, let message): return "GitHub request failed (\(code)): \(message)"
        }
    }
}

struct GitHubErrorMessage: Decodable {
    let message: String
}

struct GitHubUser: Decodable, Equatable {
    let login: String
    let avatarUrl: String?
    let htmlUrl: String?
}

struct GitHubUserSummary: Decodable, Equatable {
    let login: String
    let avatarUrl: String?
    let htmlUrl: String?
    let type: String

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl
        case htmlUrl
        case type
    }

    init(login: String, avatarUrl: String? = nil, htmlUrl: String? = nil, type: String = "User") {
        self.login = login
        self.avatarUrl = avatarUrl
        self.htmlUrl = htmlUrl
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        login = try container.decode(String.self, forKey: .login)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        htmlUrl = try container.decodeIfPresent(String.self, forKey: .htmlUrl)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "User"
    }
}

struct GitHubLabel: Decodable, Equatable {
    let name: String
}

struct GitHubSearchResponse: Decodable, Equatable {
    let totalCount: Int
    let incompleteResults: Bool
    let items: [GitHubSearchItem]
}

struct GitHubSearchItem: Decodable, Equatable {
    let url: String
    let repositoryUrl: String
    let htmlUrl: String
    let number: Int
    let title: String
    let body: String?
    let state: String
    let labels: [GitHubLabel]
    let user: GitHubUserSummary
    let comments: Int?
    let updatedAt: Date
    let createdAt: Date
    let pullRequest: GitHubPullRequestReference?
}

struct GitHubPullRequestReference: Decodable, Equatable {
    let url: String?
    let htmlUrl: String?
    let mergedAt: Date?
}

struct GitHubPullRequestResponse: Decodable, Equatable {
    let htmlUrl: String
    let number: Int
    let state: String
    let title: String
    let body: String?
    let draft: Bool?
    let mergedAt: Date?
    let mergeable: Bool?
    let mergeableState: String?
    let user: GitHubUserSummary
    let labels: [GitHubLabel]?
    let head: GitHubBranch
    let base: GitHubBranch
    let changedFiles: Int?
    let additions: Int?
    let deletions: Int?
    let updatedAt: Date
}

struct GitHubBranch: Decodable, Equatable {
    let sha: String
}

struct GitHubIssueResponse: Decodable, Equatable {
    let htmlUrl: String
    let number: Int
    let state: String
    let title: String
    let body: String?
    let labels: [GitHubLabel]
    let user: GitHubUserSummary
    let assignees: [GitHubUserSummary]?
    let updatedAt: Date
    let closedAt: Date?
}

struct GitHubComment: Decodable, Equatable {
    let id: Int
    let body: String
    let user: GitHubUserSummary
    let htmlUrl: String?
    let createdAt: Date
    let updatedAt: Date
}

struct GitHubRepositoryResponse: Decodable, Equatable {
    let fullName: String
    let archived: Bool
    let defaultBranch: String?
}

struct GitHubCheckRunsResponse: Decodable, Equatable {
    let totalCount: Int
    let checkRuns: [GitHubCheckRun]
}

struct GitHubCheckRun: Decodable, Equatable {
    let name: String
    let status: String
    let conclusion: String?
}

struct GitHubCombinedStatusResponse: Decodable, Equatable {
    let state: String
    let statuses: [GitHubCommitStatus]
}

struct GitHubCommitStatus: Decodable, Equatable {
    let state: String
    let context: String?
    let description: String?
}

struct GitHubContentFile: Decodable, Equatable {
    let type: String
    let encoding: String?
    let content: String?
}

extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
