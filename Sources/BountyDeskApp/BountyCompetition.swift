import Foundation

struct CompetitorSummary: Equatable {
    var prNumber: Int?
    var prUrl: String?
    var author: String
    var title: String?
    var state: CompetitorState
    var merged: Bool
    var rewardSeen: Bool
    var checksSummary: String?
    var claimSeen: Bool
    var updatedAt: Date?
    var evidence: [String]
    var isDraft: Bool = false
    var serious: Bool = false
    var mergeable: Bool? = nil
    var mergeableState: String? = nil
}

struct BountyCompetitionReport: Equatable {
    var repo: String
    var issueNumber: Int
    var issueUrl: String
    var issueTitle: String
    var issueState: IssueState

    var source: AlgoraOnlyBountySource
    var algoraVerified: Bool
    var algoraBotSeen: Bool
    var bountyAmountUsd: Int?
    var claimFlowSeen: Bool
    var rewardActionSeen: Bool

    var ourPrNumber: Int?
    var ourPrUrl: String?
    var ourPrState: PullRequestState?
    var ourPrMerged: Bool
    var ourPrMergeable: Bool?
    var ourPrMergeableState: String?
    var ourCheckSummary: String
    var ourPaidSignal: Bool

    var totalAttemptsFromAlgoraTable: Int
    var openClaimPrs: Int
    var closedClaimPrs: Int
    var mergedClaimPrs: Int
    var rewardedClaims: Int
    var seriousOpenCompetitors: Int

    var competitionLevel: CompetitionLevel
    var competitors: [CompetitorSummary]
    var recommendation: BountyRecommendation
    var reasons: [String]
    var lastCheckedAt: Date

    static func notAlgora(issue: GitHubIssueResponse, repo: String, reason: String, verification: AlgoraBountyVerification? = nil, lastCheckedAt: Date = Date()) -> BountyCompetitionReport {
        BountyCompetitionReport(
            repo: repo,
            issueNumber: issue.number,
            issueUrl: issue.htmlUrl,
            issueTitle: issue.title,
            issueState: issue.state.lowercased() == "closed" ? .closed : .open,
            source: .notAlgora,
            algoraVerified: false,
            algoraBotSeen: verification?.algoraBotSeen ?? false,
            bountyAmountUsd: verification?.amountUsd,
            claimFlowSeen: verification?.claimFlowSeen ?? false,
            rewardActionSeen: verification?.rewardActionSeen ?? false,
            ourPrNumber: nil,
            ourPrUrl: nil,
            ourPrState: nil,
            ourPrMerged: false,
            ourPrMergeable: nil,
            ourPrMergeableState: nil,
            ourCheckSummary: "none",
            ourPaidSignal: false,
            totalAttemptsFromAlgoraTable: 0,
            openClaimPrs: 0,
            closedClaimPrs: 0,
            mergedClaimPrs: 0,
            rewardedClaims: 0,
            seriousOpenCompetitors: 0,
            competitionLevel: .none,
            competitors: [],
            recommendation: .notAlgora,
            reasons: [reason],
            lastCheckedAt: lastCheckedAt
        )
    }
}


extension CompetitorState {
    var pullRequestState: PullRequestState {
        switch self {
        case .attemptOnly: return .unknown
        case .openPr: return .open
        case .mergedPr, .rewarded: return .merged
        case .closedPr: return .closed
        case .unknown: return .unknown
        }
    }
}
