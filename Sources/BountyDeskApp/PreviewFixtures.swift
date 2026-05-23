import Foundation
import SwiftData
import SwiftUI

#if DEBUG
enum PreviewFixtures {
    static var sampleSnapshot: TrackedBountySnapshot {
        TrackedBountySnapshot(
            stableID: "mock:example/repo#42:pr99",
            source: .mock,
            repoOwner: "example",
            repoName: "repo",
            issueNumber: 42,
            linkedPullRequestNumber: 99,
            title: "Add streaming export support",
            issueBodySummary: "Mock issue summary for previews only.",
            pullRequestSummary: "Mock PR summary with verification steps and tests.",
            amount: 500,
            labels: ["Algora", "Bounty", "$500"],
            algoraEvidence: ["Verified Algora bounty", "Official Algora issue comment found", "$500 bounty", "Algora claim flow found"],
            rewardLinks: ["https://algora.io/example/repo/issues/42"],
            workflowStatus: .pendingReview,
            issueState: .open,
            claimStatus: .accepted,
            checkState: .passing,
            riskLevel: .low,
            payoutChance: 86,
            riskFactors: ["Checks are passing", "Claim appears accepted", "Low competition"],
            nextAction: "Keep the PR current and respond to maintainer feedback.",
            latestMaintainerComment: "Looks close. Please add one more regression test.",
            latestBotComment: "$500 bounty. Start working: /attempt #42. Submit work: /claim #42.",
            competitionCount: 1,
            hasRewardedSignal: false,
            requiresVideo: false,
            hasDemoProof: false,
            repoArchived: false,
            assignedOnly: false,
            userAppearsAssigned: false,
            maintainerAssignmentRequired: false,
            priorRejectedSignal: false,
            hasClearVerification: true,
            hasTests: true,
            createdAt: Date().addingTimeInterval(-86_400),
            updatedAt: Date(),
            lastRefreshedAt: Date()
        )
    }

    @MainActor
    static func viewModel() -> BountyTrackerViewModel {
        let viewModel = BountyTrackerViewModel()
        viewModel.isAuthenticated = true
        viewModel.hasGitHubToken = true
        viewModel.authenticatedLogin = "preview-user"
        return viewModel
    }

    @MainActor
    static func container() -> ModelContainer {
        let schema = Schema([
            UserAccount.self,
            WatchedOrg.self,
            Bounty.self,
            Claim.self,
            PullRequest.self,
            GitHubIssue.self,
            RepoRuleSet.self,
            CompetitorPR.self,
            AlertEvent.self,
            BountyChecklistItem.self,
            RiskScoreSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(UserAccount(githubLogin: "preview-user", hasGitHubToken: true, lastValidatedAt: Date()))
        context.insert(WatchedOrg(handle: "example"))
        let bounty = Bounty(snapshot: sampleSnapshot)
        context.insert(bounty)
        context.insert(AlertEvent(snapshot: AlertSnapshot(stableID: "mock-alert", bountyStableID: bounty.stableID, kind: .maintainerComment, title: "Maintainer activity", detail: bounty.latestMaintainerComment, isRead: false, createdAt: Date())))
        context.insert(BountyChecklistItem(bountyStableID: bounty.stableID, title: "Respond to maintainer test request", sortIndex: 0))
        context.insert(BountyChecklistItem(bountyStableID: bounty.stableID, title: "Watch claim payout state", isDone: true, completedAt: Date().addingTimeInterval(-3_600), sortIndex: 1))
        try? context.save()
        return container
    }
}

#Preview("BountyDesk") {
    ContentView()
        .environmentObject(PreviewFixtures.viewModel())
        .modelContainer(PreviewFixtures.container())
}
#endif
