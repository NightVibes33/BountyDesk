import Foundation

struct GitHubOAuthConfiguration {
    static let clientID = "Ov23li4ZD248FNrHQUia"

    static func scope(includePrivateRepositories: Bool) -> String {
        includePrivateRepositories ? "repo read:user" : "public_repo read:user"
    }
}

struct GitHubDeviceFlowClient {
    var baseURL = URL(string: "https://github.com")!
    var session: URLSession = .shared

    func requestDeviceCode(includePrivateRepositories: Bool) async throws -> GitHubDeviceAuthorization {
        let body = formBody([
            "client_id": GitHubOAuthConfiguration.clientID,
            "scope": GitHubOAuthConfiguration.scope(includePrivateRepositories: includePrivateRepositories)
        ])
        var request = URLRequest(url: baseURL.appendingPathComponent("login/device/code"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("BountyDesk/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let response: GitHubDeviceAuthorizationResponse = try await send(request)
        return GitHubDeviceAuthorization(response: response, includePrivateRepositories: includePrivateRepositories)
    }

    func pollForAccessToken(authorization: GitHubDeviceAuthorization) async throws -> GitHubDeviceAccessToken {
        var waitSeconds = max(authorization.interval, 1)
        while authorization.isExpired == false {
            let body = formBody([
                "client_id": GitHubOAuthConfiguration.clientID,
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            var request = URLRequest(url: baseURL.appendingPathComponent("login/oauth/access_token"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("BountyDesk/1.0", forHTTPHeaderField: "User-Agent")
            request.httpBody = body

            let response: GitHubDeviceTokenResponse = try await send(request)
            if let accessToken = response.accessToken, accessToken.isEmpty == false {
                return GitHubDeviceAccessToken(accessToken: accessToken, tokenType: response.tokenType ?? "bearer", scope: response.scope ?? "")
            }

            switch response.error {
            case "authorization_pending":
                break
            case "slow_down":
                waitSeconds += 5
            case "expired_token":
                throw GitHubDeviceFlowError.expired
            case "access_denied":
                throw GitHubDeviceFlowError.denied
            case "incorrect_client_credentials":
                throw GitHubDeviceFlowError.incorrectClientCredentials
            case let error?:
                throw GitHubDeviceFlowError.authorizationFailed(error, response.errorDescription)
            case nil:
                throw GitHubDeviceFlowError.invalidResponse
            }

            if waitSeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(waitSeconds) * 1_000_000_000)
            }
        }
        throw GitHubDeviceFlowError.expired
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubDeviceFlowError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw GitHubDeviceFlowError.httpStatus(http.statusCode, message)
        }
        return try JSONDecoder.github.decode(T.self, from: data)
    }

    private func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

struct GitHubDeviceAuthorization: Codable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let verificationUriComplete: String?
    let expiresIn: Int
    let interval: Int
    let includePrivateRepositories: Bool
    let createdAt: Date

    var verificationURL: URL? {
        URL(string: verificationUriComplete ?? verificationUri)
    }

    var scopeDescription: String {
        includePrivateRepositories ? "Private and public repositories" : "Public repositories"
    }

    var expiresAt: Date {
        createdAt.addingTimeInterval(TimeInterval(expiresIn))
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    init(response: GitHubDeviceAuthorizationResponse, includePrivateRepositories: Bool, createdAt: Date = Date()) {
        deviceCode = response.deviceCode
        userCode = response.userCode
        verificationUri = response.verificationUri
        verificationUriComplete = response.verificationUriComplete
        expiresIn = response.expiresIn
        interval = response.interval
        self.includePrivateRepositories = includePrivateRepositories
        self.createdAt = createdAt
    }
}

struct GitHubDeviceAccessToken: Equatable {
    let accessToken: String
    let tokenType: String
    let scope: String
}

struct GitHubDeviceAuthorizationResponse: Decodable, Equatable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let verificationUriComplete: String?
    let expiresIn: Int
    let interval: Int
}

struct GitHubDeviceTokenResponse: Decodable, Equatable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?
}

enum GitHubDeviceFlowError: LocalizedError, Equatable {
    case invalidResponse
    case expired
    case denied
    case incorrectClientCredentials
    case authorizationFailed(String, String?)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub returned an invalid device login response."
        case .expired: return "GitHub device login expired. Start again."
        case .denied: return "GitHub device login was denied."
        case .incorrectClientCredentials: return "GitHub rejected this OAuth client. Check that Device Flow is enabled for the OAuth app."
        case .authorizationFailed(let error, let description): return description ?? "GitHub device login failed: \(error)."
        case .httpStatus(let code, let message): return "GitHub device login failed (\(code)): \(message.trimmedSummary(limit: 160))"
        }
    }
}
