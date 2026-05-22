import Foundation

struct RiskScoringService {
    func score(_ input: RiskInput) -> RiskOutput {
        var score = 70
        var factors: [String] = []

        switch input.pullRequestState {
        case .merged:
            score += 18
            factors.append("PR is merged")
        case .open:
            score += 4
            factors.append("PR is open")
        case .draft:
            score -= 14
            factors.append("Draft PR lowers payout confidence")
        case .closed:
            score -= 35
            factors.append("PR is closed")
        case .unknown:
            score -= 8
            factors.append("PR state is unknown")
        }

        switch input.issueState {
        case .open:
            score += 4
            factors.append("Issue is still open")
        case .closed:
            score -= input.pullRequestState == .merged ? 0 : 18
            factors.append("Issue is closed")
        case .unknown:
            score -= 4
            factors.append("Issue state is unknown")
        }

        switch input.checkState {
        case .passing:
            score += 12
            factors.append("Checks are passing")
        case .failing:
            score -= 22
            factors.append("Checks are failing")
        case .pending:
            score -= 6
            factors.append("Checks are pending")
        case .noneConfigured:
            score -= 2
            factors.append("No checks are configured")
        case .unknown:
            score -= 5
            factors.append("Check state is unknown")
        }

        switch input.claimStatus {
        case .paymentSucceeded:
            score = max(score, 98)
            factors.append("Payment succeeded signal found")
        case .paymentProcessing:
            score = max(score, 90)
            factors.append("Payment processing signal found")
        case .accepted:
            score += 15
            factors.append("Claim appears accepted")
        case .pending:
            score += 3
            factors.append("Claim appears pending")
        case .rejected:
            score -= 40
            factors.append("Claim appears rejected")
        case .unknown:
            factors.append("Claim status is unknown")
        }

        if input.mergeableState.lowercased().contains("dirty") || input.mergeableState.lowercased().contains("blocked") {
            score -= 15
            factors.append("Mergeability is blocked")
        }
        if input.hasMaintainerComment {
            score += 4
            factors.append("Maintainer activity found")
        }
        if input.competitionCount >= 8 {
            score -= 18
            factors.append("High competition")
        } else if input.competitionCount >= 3 {
            score -= 8
            factors.append("Moderate competition")
        } else {
            score += 5
            factors.append("Low competition")
        }
        if input.competitorMerged {
            score -= 35
            factors.append("A competitor PR is merged")
        }
        if input.issueAlreadyRewarded {
            score -= 45
            factors.append("Bounty appears already rewarded or paid")
        }
        if input.assignmentRequired && input.userAppearsAssigned == false {
            score -= 24
            factors.append("Assignment appears required but user is not assigned")
        }
        if input.demoVideoRequired && input.demoProofPresent == false {
            score -= 18
            factors.append("Demo video appears required but missing")
        }
        if input.repoArchived {
            score -= 35
            factors.append("Repository is archived")
        }
        if input.priorRejectedSignal {
            score -= 18
            factors.append("Prior rejection or block signal found")
        }
        if input.hasClearVerification {
            score += 6
            factors.append("PR includes clear verification")
        }
        if input.hasTests {
            score += 8
            factors.append("PR includes tests or test evidence")
        }
        if input.contributingRulesFound {
            factors.append("CONTRIBUTING rules found")
        }
        if input.codeOfConductFound {
            factors.append("Code of Conduct found")
        }

        let clamped = min(100, max(0, score))
        let level: RiskLevel
        if clamped >= 75 {
            level = .low
        } else if clamped >= 45 {
            level = .medium
        } else {
            level = .high
        }

        return RiskOutput(score: clamped, level: level, factors: factors, nextAction: nextAction(for: input, level: level))
    }

    private func nextAction(for input: RiskInput, level: RiskLevel) -> String {
        if input.repoArchived { return "Do not pursue until the repository is active again." }
        if input.issueAlreadyRewarded { return "Do not spend more time unless a maintainer confirms the bounty is still open." }
        if input.pullRequestState == .closed { return "Review the closure reason before doing more work." }
        if input.checkState == .failing { return "Fix failing checks before asking for review." }
        if input.demoVideoRequired && input.demoProofPresent == false { return "Add real demo proof if the repository requires it." }
        if input.assignmentRequired && input.userAppearsAssigned == false { return "Ask for assignment before investing more time." }
        if input.competitorMerged { return "Compare scope with the merged competitor PR and avoid duplicated work." }
        if input.hasClearVerification == false { return "Add concise verification steps to the PR body." }
        if input.hasTests == false { return "Add tests or explain why tests are not applicable." }
        switch input.claimStatus {
        case .paymentProcessing: return "Monitor payout status; payment processing has started."
        case .paymentSucceeded: return "Mark paid after confirming the transfer."
        case .accepted: return "Watch for payment updates and maintainer follow-up."
        default: break
        }
        return level == .low ? "Keep the PR current and respond to maintainer feedback." : "Reduce risk before spending significant time."
    }
}

struct RiskInput: Equatable {
    var pullRequestState: PullRequestState
    var issueState: IssueState
    var checkState: CheckState
    var claimStatus: ClaimStatus
    var mergeableState: String
    var hasMaintainerComment: Bool
    var competitionCount: Int
    var competitorMerged: Bool
    var issueAlreadyRewarded: Bool
    var assignmentRequired: Bool
    var userAppearsAssigned: Bool
    var demoVideoRequired: Bool
    var demoProofPresent: Bool
    var repoArchived: Bool
    var priorRejectedSignal: Bool
    var hasClearVerification: Bool
    var hasTests: Bool
    var contributingRulesFound: Bool
    var codeOfConductFound: Bool
}

struct RiskOutput: Equatable {
    var score: Int
    var level: RiskLevel
    var factors: [String]
    var nextAction: String
}
