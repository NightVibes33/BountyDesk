import Foundation

struct AlgoraPublicClient {
    var baseURL = URL(string: "https://console.algora.io")!
    var session: URLSession = .shared

    func bounties(org: String, limit: Int = 100) async throws -> [AlgoraBountyDTO] {
        try await requestOrgCollection(path: "/api/orgs/\(org)/bounties", limit: limit)
    }

    func claims(org: String, limit: Int = 100) async throws -> [AlgoraClaimDTO] {
        try await requestOrgCollection(path: "/api/orgs/\(org)/claims", limit: limit)
    }

    private func requestOrgCollection<T: Decodable>(path: String, limit: Int) async throws -> [T] {
        guard let url = endpoint(path: path, limit: limit) else { throw AlgoraAPIError.invalidURL }
        return try await requestCollection(url: url, token: nil)
    }

    private func endpoint(path: String, limit: Int) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        return components?.url
    }

    func requestCollection<T: Decodable>(url: URL, token: String?) async throws -> [T] {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BountyDesk/1.0", forHTTPHeaderField: "User-Agent")
        if let token, token.isEmpty == false {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AlgoraAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AlgoraAPIError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder.algora
        if let envelope = try? decoder.decode(AlgoraCollectionEnvelope<T>.self, from: data) {
            return envelope.items
        }
        if let array = try? decoder.decode([T].self, from: data) {
            return array
        }
        throw AlgoraAPIError.unexpectedShape
    }
}

struct AlgoraAuthenticatedClient {
    var baseURL = URL(string: "https://console.algora.io")!
    var session: URLSession = .shared
    var token: String?

    var isConfigured: Bool {
        token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func bounties(limit: Int = 100) async throws -> [AlgoraBountyDTO] {
        try await collection(path: "/api/bounties", limit: limit)
    }

    func claims(limit: Int = 100) async throws -> [AlgoraClaimDTO] {
        try await collection(path: "/api/claims", limit: limit)
    }

    func orgBounties(org: String, limit: Int = 100) async throws -> [AlgoraBountyDTO] {
        try await collection(path: "/api/orgs/\(org)/bounties", limit: limit)
    }

    func orgClaims(org: String, limit: Int = 100) async throws -> [AlgoraClaimDTO] {
        try await collection(path: "/api/orgs/\(org)/claims", limit: limit)
    }

    private func collection<T: Decodable>(path: String, limit: Int) async throws -> [T] {
        guard let token, token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AlgoraAPIError.missingToken
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        guard let url = components?.url else { throw AlgoraAPIError.invalidURL }
        return try await AlgoraPublicClient(baseURL: baseURL, session: session).requestCollection(url: url, token: token)
    }
}

enum AlgoraAPIError: LocalizedError, Equatable {
    case missingToken
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case unexpectedShape

    var errorDescription: String? {
        switch self {
        case .missingToken: return "No Algora API token is configured."
        case .invalidURL: return "Invalid Algora URL."
        case .invalidResponse: return "Algora returned an invalid response."
        case .httpStatus(let code, let body): return "Algora request failed (\(code)): \(body.trimmedSummary(limit: 160))"
        case .unexpectedShape: return "Algora returned data in an unsupported shape."
        }
    }
}

struct AlgoraCollectionEnvelope<T: Decodable>: Decodable {
    let items: [T]
}

struct AlgoraBountyDTO: Decodable, Equatable {
    let id: String?
    let status: String?
    let rewardFormatted: String?
    let reward: AlgoraRewardDTO?
    let task: AlgoraTaskDTO?
    let claims: [AlgoraClaimDTO]?
    let updatedAt: Date?
    let createdAt: Date?
}

struct AlgoraTaskDTO: Decodable, Equatable {
    let number: Int?
    let repoOwner: String?
    let repoName: String?
    let title: String?
    let body: String?
    let url: String?
}

struct AlgoraRewardDTO: Decodable, Equatable {
    let amount: Int?
    let currency: String?
}

struct AlgoraClaimDTO: Decodable, Equatable {
    let id: String?
    let status: String?
    let url: String?
    let pullRequestId: Int?
    let transferAmount: Int?
    let transferCurrency: String?
    let solver: AlgoraSolverDTO?
    let updatedAt: Date?
    let createdAt: Date?
}

struct AlgoraSolverDTO: Decodable, Equatable {
    let login: String?
    let htmlUrl: String?
}

extension JSONDecoder {
    static var algora: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: text) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(text)")
        }
        return decoder
    }
}
