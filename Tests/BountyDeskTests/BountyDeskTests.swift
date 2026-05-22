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

    func testVideoAndVerificationParsing() {
        XCTAssertTrue(BountyParsing.requiresVideo(in: "A demo video is required."))
        XCTAssertTrue(BountyParsing.hasDemoProof(in: "Demo: https://loom.com/share/abc"))
        XCTAssertTrue(BountyParsing.hasClearVerification(in: "Steps to test: run npm test"))
        XCTAssertTrue(BountyParsing.hasTests(in: "I ran swift test and added coverage."))
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

    static func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
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
