import XCTest
@testable import BountyDesk

final class BountyParsingTests: XCTestCase {
    func testClaimDetection() {
        XCTAssertTrue(BountyParsing.containsClaimMarker("@algora-pbc /claim"))
        XCTAssertTrue(BountyParsing.containsClaimMarker("I would like to /claim this bounty"))
        XCTAssertFalse(BountyParsing.containsClaimMarker("regular maintenance PR"))
    }

    func testLinkedIssueExtraction() {
        let issues = BountyParsing.linkedIssueNumbers(in: "Fixes #42 and closes https://github.com/org/repo/issues/77")
        XCTAssertEqual(issues, [42, 77])
    }

    func testClaimIssueExtractionPrioritizesAlgoraClaimMarker() {
        let text = "Refs #3 while implementing @algora-pbc /claim #152 and mentions #8 later"
        XCTAssertEqual(BountyParsing.claimIssueNumbers(in: text), [152])
        XCTAssertEqual(BountyParsing.linkedIssueNumbers(in: text), [3])
    }

    func testBountyAmountParsing() {
        XCTAssertEqual(BountyParsing.bountyAmount(in: "[ Bounty $4k ] Add exporter compatibility"), 4_000)
        XCTAssertEqual(BountyParsing.bountyAmount(in: "Total prize pool: $1,250"), 1_250)
        XCTAssertEqual(BountyParsing.bountyAmount(in: "reward 300 USD"), 300)
    }

    func testAlgoraEvidenceParsing() {
        let labels = ["💎 Bounty", "bug"]
        let comments = ["Algora bot: Status Pending", "Total prize pool $500"]
        XCTAssertTrue(BountyParsing.hasAlgoraEvidence(labels: labels, body: "", comments: comments))
        XCTAssertEqual(BountyParsing.claimStatus(in: comments.joined(separator: "\n")), .pending)
    }

    func testPaymentStatusParsing() {
        XCTAssertEqual(BountyParsing.paymentStatus(in: "claim moved to payment_processing"), .paymentProcessing)
        XCTAssertEqual(BountyParsing.paymentStatus(in: "payment_succeeded"), .paymentSucceeded)
    }

    func testVideoVerificationAndRewardLinkParsing() {
        XCTAssertTrue(BountyParsing.requiresVideo(in: "A demo video is required."))
        XCTAssertTrue(BountyParsing.hasDemoProof(in: "Demo: https://loom.com/share/abc"))
        XCTAssertTrue(BountyParsing.hasClearVerification(in: "Steps to test: run npm test"))
        XCTAssertTrue(BountyParsing.hasTests(in: "I ran swift test and added coverage."))
        XCTAssertEqual(BountyParsing.rewardLinks(in: "Reward: https://console.algora.io/org/repo/bounties/42"), ["https://console.algora.io/org/repo/bounties/42"])
    }
}


final class DiscoverFiltersTests: XCTestCase {
    func testRecentlyUpdatedFilterRejectsOldBounties() {
        var filters = DiscoverFilters()
        filters.onlyAlgoraEvidence = false
        filters.recentlyUpdated = true
        let old = Self.snapshot(updatedAt: Date().addingTimeInterval(-60.0 * 24.0 * 60.0 * 60.0))
        XCTAssertFalse(filters.matches(snapshot: old, commentCount: 0))
    }

    func testMinimumPayoutRejectsUnknownAmountWhenConfigured() {
        var filters = DiscoverFilters()
        filters.onlyAlgoraEvidence = false
        filters.minimumPayout = 500
        let unknownAmount = Self.snapshot(amount: 0)
        XCTAssertFalse(filters.matches(snapshot: unknownAmount, commentCount: 0))
        XCTAssertTrue(filters.matches(snapshot: Self.snapshot(amount: 750), commentCount: 0))
    }

    private static func snapshot(amount: Int = 500, updatedAt: Date = Date()) -> TrackedBountySnapshot {
        TrackedBountySnapshot(
            stableID: "test:org/repo#1",
            source: .github,
            repoOwner: "org",
            repoName: "repo",
            issueNumber: 1,
            linkedPullRequestNumber: nil,
            title: "Test bounty",
            issueBodySummary: "",
            pullRequestSummary: "",
            amount: amount,
            labels: [],
            algoraEvidence: ["Algora reference found"],
            rewardLinks: [],
            workflowStatus: .watching,
            issueState: .open,
            claimStatus: .unknown,
            checkState: .unknown,
            riskLevel: .medium,
            payoutChance: 50,
            riskFactors: [],
            nextAction: "Review",
            latestMaintainerComment: "",
            latestBotComment: "",
            competitionCount: 0,
            hasRewardedSignal: false,
            requiresVideo: false,
            hasDemoProof: false,
            repoArchived: false,
            assignedOnly: false,
            userAppearsAssigned: false,
            maintainerAssignmentRequired: false,
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastRefreshedAt: nil
        )
    }
}

final class RiskScoringTests: XCTestCase {
    func testRiskScoringLowRiskPaymentProcessing() {
        let output = RiskScoringService().score(RiskInput(
            pullRequestState: .merged,
            issueState: .open,
            checkState: .passing,
            claimStatus: .paymentProcessing,
            mergeableState: "clean",
            hasMaintainerComment: true,
            competitionCount: 1,
            competitorMerged: false,
            issueAlreadyRewarded: false,
            assignmentRequired: false,
            userAppearsAssigned: false,
            demoVideoRequired: false,
            demoProofPresent: false,
            repoArchived: false,
            priorRejectedSignal: false,
            hasClearVerification: true,
            hasTests: true,
            contributingRulesFound: true,
            codeOfConductFound: true
        ))
        XCTAssertEqual(output.level, .low)
        XCTAssertGreaterThanOrEqual(output.score, 90)
        XCTAssertTrue(output.factors.contains("Payment processing signal found"))
    }

    func testRiskScoringHighRiskFailingCrowdedArchived() {
        let output = RiskScoringService().score(RiskInput(
            pullRequestState: .closed,
            issueState: .closed,
            checkState: .failing,
            claimStatus: .unknown,
            mergeableState: "dirty",
            hasMaintainerComment: false,
            competitionCount: 12,
            competitorMerged: true,
            issueAlreadyRewarded: true,
            assignmentRequired: true,
            userAppearsAssigned: false,
            demoVideoRequired: true,
            demoProofPresent: false,
            repoArchived: true,
            priorRejectedSignal: true,
            hasClearVerification: false,
            hasTests: false,
            contributingRulesFound: false,
            codeOfConductFound: false
        ))
        XCTAssertEqual(output.level, .high)
        XCTAssertLessThan(output.score, 45)
        XCTAssertEqual(output.nextAction, "Do not pursue until the repository is active again.")
    }
}

final class GitHubClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testGitHubTokenValidationCallsUser() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/user")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let data = #"{"login":"tester","avatar_url":null,"html_url":"https://github.com/tester"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let user = try await GitHubClient(session: Self.mockSession()).validateToken("secret")
        XCTAssertEqual(user.login, "tester")
    }

    func testPRSearchParsingAndDeduping() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/search/issues")
            let json = """
            {
              "total_count": 1,
              "incomplete_results": false,
              "items": [
                {
                  "url": "https://api.github.com/repos/org/repo/issues/5",
                  "repository_url": "https://api.github.com/repos/org/repo",
                  "html_url": "https://github.com/org/repo/pull/5",
                  "number": 5,
                  "title": "Claim bounty",
                  "body": "@algora-pbc /claim fixes #3",
                  "state": "open",
                  "labels": [{"name":"🙋 Bounty claim"}],
                  "user": {"login":"tester","avatar_url":null,"html_url":"https://github.com/tester","type":"User"},
                  "comments": 2,
                  "updated_at": "2026-05-22T04:00:00Z",
                  "created_at": "2026-05-22T03:00:00Z",
                  "pull_request": {"url":"https://api.github.com/repos/org/repo/pulls/5","html_url":"https://github.com/org/repo/pull/5","merged_at":null}
                }
              ]
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let items = try await GitHubClient(session: Self.mockSession()).searchClaimPullRequests(username: "tester", token: "secret")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].number, 5)
        XCTAssertEqual(GitHubClient.repositorySlug(from: items[0].repositoryUrl)?.owner, "org")
    }

    func testPRSearchContinuesAfterSingleQueryFailure() async throws {
        var queries: [String] = []
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/search/issues")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            queries.append(query)
            if query.contains("/claim") {
                let data = #"{"message":"Validation Failed"}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!, data)
            }
            let items = query.contains("\"@algora-pbc\"") ? """
                [{
                  "url": "https://api.github.com/repos/org/repo/issues/6",
                  "repository_url": "https://api.github.com/repos/org/repo",
                  "html_url": "https://github.com/org/repo/pull/6",
                  "number": 6,
                  "title": "Claim bounty after failed query",
                  "body": "@algora-pbc /claim fixes #4",
                  "state": "open",
                  "labels": [],
                  "user": {"login":"tester","avatar_url":null,"html_url":"https://github.com/tester","type":"User"},
                  "comments": 1,
                  "updated_at": "2026-05-22T05:00:00Z",
                  "created_at": "2026-05-22T04:00:00Z",
                  "pull_request": {"url":"https://api.github.com/repos/org/repo/pulls/6","html_url":"https://github.com/org/repo/pull/6","merged_at":null}
                }]
                """ : "[]"
            let json = """
            {"total_count":1,"incomplete_results":false,"items":\(items)}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let items = try await GitHubClient(session: Self.mockSession()).searchClaimPullRequests(username: "tester", token: "secret")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].number, 6)
        XCTAssertTrue(queries.contains { $0.contains("\"@algora-pbc\"") })
    }

    func testRefreshUsesClaimIssueNumberBeforeIncidentalReferences() async {
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            let body: String
            let status: Int
            switch path {
            case "/user":
                status = 200
                body = #"{"login":"tester","avatar_url":null,"html_url":"https://github.com/tester"}"#
            case "/search/issues" where query.contains("/claim"):
                status = 200
                body = #"{"total_count":1,"incomplete_results":false,"items":[{"url":"https://api.github.com/repos/org/repo/issues/10","repository_url":"https://api.github.com/repos/org/repo","html_url":"https://github.com/org/repo/pull/10","number":10,"title":"Claim bounty","body":"/claim #42\nRefs #3","state":"open","labels":[{"name":"🙋 Bounty claim"}],"user":{"login":"tester","avatar_url":null,"html_url":"https://github.com/tester","type":"User"},"comments":0,"updated_at":"2026-05-22T04:00:00Z","created_at":"2026-05-22T03:00:00Z","pull_request":{"url":"https://api.github.com/repos/org/repo/pulls/10","html_url":"https://github.com/org/repo/pull/10","merged_at":null}}]}"#
            case "/search/issues":
                status = 200
                body = #"{"total_count":0,"incomplete_results":false,"items":[]}"#
            case "/repos/org/repo/pulls/10":
                status = 200
                body = #"{"html_url":"https://github.com/org/repo/pull/10","number":10,"state":"open","title":"Claim bounty","body":"/claim #42\nRefs #3\n\nTests: npm test","draft":false,"merged_at":null,"mergeable":true,"mergeable_state":"clean","user":{"login":"tester","avatar_url":null,"html_url":"https://github.com/tester","type":"User"},"labels":[{"name":"🙋 Bounty claim"}],"head":{"sha":"abc"},"base":{"sha":"base"},"changed_files":2,"additions":20,"deletions":3,"updated_at":"2026-05-22T04:00:00Z"}"#
            case "/repos/org/repo/issues/10/comments":
                status = 200
                body = "[]"
            case "/repos/org/repo/issues/42":
                status = 200
                body = #"{"html_url":"https://github.com/org/repo/issues/42","number":42,"state":"open","title":"Build the paid feature","body":"Total prize pool: $1,000\n@algora-pbc /bounty","labels":[{"name":"💎 Bounty"}],"user":{"login":"maintainer","avatar_url":null,"html_url":"https://github.com/maintainer","type":"User"},"assignees":[],"updated_at":"2026-05-22T02:00:00Z","closed_at":null}"#
            case "/repos/org/repo/issues/42/comments":
                status = 200
                body = #"[{"id":1,"body":"Algora bot: Status Pending","user":{"login":"algora-pbc","avatar_url":null,"html_url":"https://github.com/algora-pbc","type":"Bot"},"html_url":"https://github.com/org/repo/issues/42#issuecomment-1","created_at":"2026-05-22T02:30:00Z","updated_at":"2026-05-22T02:30:00Z"}]"#
            case "/repos/org/repo":
                status = 200
                body = #"{"full_name":"org/repo","archived":false,"default_branch":"main"}"#
            case "/repos/org/repo/commits/abc/check-runs":
                status = 200
                body = #"{"total_count":0,"check_runs":[]}"#
            case "/repos/org/repo/commits/abc/status":
                status = 200
                body = #"{"state":"success","statuses":[]}"#
            default:
                status = path.contains("/contents/") ? 404 : 500
                body = #"{"message":"not found"}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body.data(using: .utf8)!)
        }
        let session = Self.mockSession()
        let service = BountyTrackerService(
            github: GitHubClient(session: session),
            algoraPublic: AlgoraPublicClient(session: session),
            riskScoring: RiskScoringService()
        )
        let result = await service.refreshCurrentBounties(githubToken: "secret", algoraToken: nil, watchedOrgs: [])
        XCTAssertEqual(result.claimPullRequestCount, 1)
        XCTAssertEqual(result.activeClaimPullRequestCount, 1)
        XCTAssertEqual(result.bounties.count, 1)
        XCTAssertEqual(result.bounties[0].issueNumber, 42)
        XCTAssertEqual(result.bounties[0].linkedPullRequestNumber, 10)
        XCTAssertEqual(result.bounties[0].amount, 1_000)
        XCTAssertEqual(result.bounties[0].title, "Build the paid feature")
    }

    func testRecentAuthoredPullRequestSearchUsesBroadOpenClosedQueries() async throws {
        var queries: [String] = []
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/search/issues")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            queries.append(query)
            let items = query.contains("state:open") ? """
                [{
                  "url": "https://api.github.com/repos/org/repo/issues/9",
                  "repository_url": "https://api.github.com/repos/org/repo",
                  "html_url": "https://github.com/org/repo/pull/9",
                  "number": 9,
                  "title": "Fix linked bounty",
                  "body": "Fixes #42",
                  "state": "open",
                  "labels": [],
                  "user": {"login":"tester","avatar_url":null,"html_url":"https://github.com/tester","type":"User"},
                  "comments": 0,
                  "updated_at": "2026-05-22T04:00:00Z",
                  "created_at": "2026-05-22T03:00:00Z",
                  "pull_request": {"url":"https://api.github.com/repos/org/repo/pulls/9","html_url":"https://github.com/org/repo/pull/9","merged_at":null}
                }]
                """ : "[]"
            let json = """
            {"total_count":1,"incomplete_results":false,"items":\(items)}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let items = try await GitHubClient(session: Self.mockSession()).searchRecentAuthoredPullRequests(username: "tester", token: "secret")
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(queries.contains { $0.contains("state:open") })
        XCTAssertTrue(queries.contains { $0.contains("state:closed") })
    }

    func testRefreshFindsBountyFromRecentPRLinkedIssue() async {
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value ?? ""
            let body: String
            let status: Int
            switch path {
            case "/user":
                status = 200
                body = #"{"login":"tester","avatar_url":null,"html_url":"https://github.com/tester"}"#
            case "/search/issues" where query.contains("author:tester is:pr state:open"):
                status = 200
                body = #"{"total_count":1,"incomplete_results":false,"items":[{"url":"https://api.github.com/repos/org/repo/issues/9","repository_url":"https://api.github.com/repos/org/repo","html_url":"https://github.com/org/repo/pull/9","number":9,"title":"Fix linked bounty","body":"Fixes #42","state":"open","labels":[],"user":{"login":"tester","avatar_url":null,"html_url":"https://github.com/tester","type":"User"},"comments":0,"updated_at":"2026-05-22T04:00:00Z","created_at":"2026-05-22T03:00:00Z","pull_request":{"url":"https://api.github.com/repos/org/repo/pulls/9","html_url":"https://github.com/org/repo/pull/9","merged_at":null}}]}"#
            case "/search/issues" where query.contains("author:tester is:pr state:closed"):
                status = 200
                body = #"{"total_count":0,"incomplete_results":false,"items":[]}"#
            case "/search/issues":
                status = 422
                body = #"{"message":"Validation Failed"}"#
            case "/repos/org/repo/pulls/9":
                status = 200
                body = #"{"html_url":"https://github.com/org/repo/pull/9","number":9,"state":"open","title":"Fix linked bounty","body":"Fixes #42\n\nTests: npm test","draft":false,"merged_at":null,"mergeable":true,"mergeable_state":"clean","user":{"login":"tester","avatar_url":null,"html_url":"https://github.com/tester","type":"User"},"labels":[],"head":{"sha":"abc"},"base":{"sha":"base"},"changed_files":2,"additions":20,"deletions":3,"updated_at":"2026-05-22T04:00:00Z"}"#
            case "/repos/org/repo/issues/9/comments":
                status = 200
                body = "[]"
            case "/repos/org/repo/issues/42":
                status = 200
                body = #"{"html_url":"https://github.com/org/repo/issues/42","number":42,"state":"open","title":"Add bounty feature","body":"Total prize pool: $750\n@algora-pbc /bounty","labels":[{"name":"💎 Bounty"}],"user":{"login":"maintainer","avatar_url":null,"html_url":"https://github.com/maintainer","type":"User"},"assignees":[],"updated_at":"2026-05-22T02:00:00Z","closed_at":null}"#
            case "/repos/org/repo/issues/42/comments":
                status = 200
                body = #"[{"id":1,"body":"Algora bot: Status Pending","user":{"login":"algora-pbc","avatar_url":null,"html_url":"https://github.com/algora-pbc","type":"Bot"},"html_url":"https://github.com/org/repo/issues/42#issuecomment-1","created_at":"2026-05-22T02:30:00Z","updated_at":"2026-05-22T02:30:00Z"}]"#
            case "/repos/org/repo":
                status = 200
                body = #"{"full_name":"org/repo","archived":false,"default_branch":"main"}"#
            case "/repos/org/repo/commits/abc/check-runs":
                status = 200
                body = #"{"total_count":0,"check_runs":[]}"#
            case "/repos/org/repo/commits/abc/status":
                status = 200
                body = #"{"state":"success","statuses":[]}"#
            default:
                status = path.contains("/contents/") ? 404 : 500
                body = #"{"message":"not found"}"#
            }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body.data(using: .utf8)!)
        }
        let session = Self.mockSession()
        let service = BountyTrackerService(
            github: GitHubClient(session: session),
            algoraPublic: AlgoraPublicClient(session: session),
            riskScoring: RiskScoringService()
        )
        let result = await service.refreshCurrentBounties(githubToken: "secret", algoraToken: nil, watchedOrgs: [])
        XCTAssertEqual(result.scannedPullRequestCount, 1)
        XCTAssertEqual(result.claimPullRequestCount, 0)
        XCTAssertEqual(result.linkedIssueCheckCount, 1)
        XCTAssertTrue(result.warnings.contains { $0.contains("Claim PR search failed") })
        XCTAssertEqual(result.bounties.count, 1)
        XCTAssertEqual(result.bounties[0].issueNumber, 42)
        XCTAssertEqual(result.bounties[0].linkedPullRequestNumber, 9)
        XCTAssertEqual(result.bounties[0].amount, 750)
    }

    static func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class GitHubDeviceFlowClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testDeviceCodeRequestUsesClientIDAndNoSecret() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/login/device/code")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = request.testBodyString
            XCTAssertTrue(body.contains("client_id=Ov23li4ZD248FNrHQUia"))
            XCTAssertTrue(body.contains("public_repo"))
            XCTAssertFalse(body.lowercased().contains("client_secret"))
            let json = #"{"device_code":"device123","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":900,"interval":0}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let authorization = try await GitHubDeviceFlowClient(session: GitHubClientTests.mockSession()).requestDeviceCode(includePrivateRepositories: false)
        XCTAssertEqual(authorization.userCode, "ABCD-EFGH")
        XCTAssertEqual(authorization.verificationURL?.absoluteString, "https://github.com/login/device")
        XCTAssertEqual(authorization.scopeDescription, "Public repositories")
    }

    func testDeviceFlowPollReturnsAccessTokenWithoutSecret() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/login/oauth/access_token")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = request.testBodyString
            XCTAssertTrue(body.contains("client_id=Ov23li4ZD248FNrHQUia"))
            XCTAssertTrue(body.contains("device_code=device123"))
            XCTAssertTrue(body.contains("grant_type="))
            XCTAssertTrue(body.contains("device_code"))
            XCTAssertFalse(body.lowercased().contains("client_secret"))
            let json = #"{"access_token":"gho_mock","token_type":"bearer","scope":"public_repo,read:user"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let authorization = GitHubDeviceAuthorization(
            response: GitHubDeviceAuthorizationResponse(deviceCode: "device123", userCode: "ABCD-EFGH", verificationUri: "https://github.com/login/device", verificationUriComplete: nil, expiresIn: 900, interval: 0),
            includePrivateRepositories: false
        )
        let token = try await GitHubDeviceFlowClient(session: GitHubClientTests.mockSession()).pollForAccessToken(authorization: authorization)
        XCTAssertEqual(token.accessToken, "gho_mock")
        XCTAssertEqual(token.tokenType, "bearer")
    }
}

final class AlgoraFallbackTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testMissingAlgoraTokenDoesNotConfigureAuthenticatedClient() async {
        let client = AlgoraAuthenticatedClient(token: nil)
        XCTAssertFalse(client.isConfigured)
        do {
            let _: [AlgoraBountyDTO] = try await client.bounties()
            XCTFail("Expected missing token error")
        } catch AlgoraAPIError.missingToken {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testDiscoverContinuesWhenPublicAlgoraFails() async {
        MockURLProtocol.handler = { request in
            if request.url?.host == "api.github.com" {
                let data = #"{"total_count":0,"incomplete_results":false,"items":[]}"#.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
            let data = #"{"message":"unavailable"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, data)
        }
        let session = GitHubClientTests.mockSession()
        let service = BountyTrackerService(
            github: GitHubClient(session: session),
            algoraPublic: AlgoraPublicClient(session: session),
            riskScoring: RiskScoringService()
        )
        var filters = DiscoverFilters()
        filters.org = "tscircuit"
        let result = await service.discoverBounties(filters: filters, githubToken: nil)
        XCTAssertEqual(result.bounties.count, 0)
        XCTAssertTrue(result.warnings.contains { $0.contains("Public Algora discovery failed") })
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var testBodyString: String {
        if let httpBody {
            return String(data: httpBody, encoding: .utf8) ?? ""
        }
        guard let httpBodyStream else { return "" }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
