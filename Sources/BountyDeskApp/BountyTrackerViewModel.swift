import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BountyTrackerViewModel: ObservableObject {
    @Published var isRestoringSession = false
    @Published var isRefreshing = false
    @Published var isDiscovering = false
    @Published var isAuthenticated = false
    @Published var hasGitHubToken = false
    @Published var hasAlgoraToken = false
    @Published var authenticatedLogin: String?
    @Published var authError: String?
    @Published var syncMessage: String?
    @Published var warnings: [String] = []
    @Published var githubDeviceAuthorization: GitHubDeviceAuthorization?
    @Published var isStartingGitHubDeviceLogin = false
    @Published var isFinishingGitHubDeviceLogin = false
    @Published var discoveredBounties: [TrackedBountySnapshot] = []
    @Published var discoverFilters = DiscoverFilters()

    private var modelContext: ModelContext?
    private let keychain = KeychainStore()
    private var service = BountyTrackerService()
    private var deviceFlow = GitHubDeviceFlowClient()

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func restoreSession() async {
        guard isRestoringSession == false else { return }
        isRestoringSession = true
        defer { isRestoringSession = false }
        do {
            let githubToken = try keychain.read(.githubToken)
            let algoraToken = try keychain.read(.algoraToken)
            hasGitHubToken = githubToken?.isEmpty == false
            hasAlgoraToken = algoraToken?.isEmpty == false
            guard let githubToken, githubToken.isEmpty == false else {
                isAuthenticated = false
                return
            }
            let user = try await service.github.validateToken(githubToken)
            authenticatedLogin = user.login
            isAuthenticated = true
            try upsertAccount(user: user, hasGitHubToken: true, hasAlgoraToken: hasAlgoraToken)
        } catch {
            isAuthenticated = false
            authError = error.localizedDescription
        }
    }

    func saveGitHubToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            authError = "Paste a GitHub personal access token."
            return
        }
        await authenticateWithGitHubToken(trimmed, successPrefix: "Signed in")
    }

    func startGitHubDeviceLogin(includePrivateRepositories: Bool) async -> URL? {
        guard isStartingGitHubDeviceLogin == false else { return githubDeviceAuthorization?.verificationURL }
        isStartingGitHubDeviceLogin = true
        defer { isStartingGitHubDeviceLogin = false }
        authError = nil
        do {
            let authorization = try await deviceFlow.requestDeviceCode(includePrivateRepositories: includePrivateRepositories)
            githubDeviceAuthorization = authorization
            syncMessage = "Open GitHub and enter code \(authorization.userCode). iOS can use your saved GitHub passkey there."
            return authorization.verificationURL
        } catch {
            authError = error.localizedDescription
            return nil
        }
    }

    func finishGitHubDeviceLogin() async {
        guard let authorization = githubDeviceAuthorization else {
            authError = "Start GitHub passkey login first."
            return
        }
        guard isFinishingGitHubDeviceLogin == false else { return }
        isFinishingGitHubDeviceLogin = true
        defer { isFinishingGitHubDeviceLogin = false }
        authError = nil
        syncMessage = "Checking GitHub passkey login..."
        do {
            let token = try await deviceFlow.pollForAccessToken(authorization: authorization)
            await authenticateWithGitHubToken(token.accessToken, successPrefix: "GitHub passkey login complete")
            if isAuthenticated { githubDeviceAuthorization = nil }
        } catch {
            authError = error.localizedDescription
        }
    }

    func resumeGitHubDeviceLoginIfNeeded() async {
        guard githubDeviceAuthorization != nil, isAuthenticated == false else { return }
        await finishGitHubDeviceLogin()
    }

    func cancelGitHubDeviceLogin() {
        githubDeviceAuthorization = nil
        syncMessage = "GitHub passkey login canceled."
    }


    private func authenticateWithGitHubToken(_ token: String, successPrefix: String) async {
        authError = nil
        do {
            let user = try await service.github.validateToken(token)
            try keychain.save(token, for: .githubToken)
            hasGitHubToken = true
            isAuthenticated = true
            authenticatedLogin = user.login
            try upsertAccount(user: user, hasGitHubToken: true, hasAlgoraToken: hasAlgoraToken)
            syncMessage = "\(successPrefix) as \(user.login)."
        } catch {
            isAuthenticated = false
            authError = error.localizedDescription
        }
    }

    func saveAlgoraToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try keychain.delete(.algoraToken)
                hasAlgoraToken = false
                syncMessage = "Algora API token removed. GitHub mode remains active."
            } else {
                try keychain.save(trimmed, for: .algoraToken)
                hasAlgoraToken = true
                syncMessage = "Optional Algora API token saved. If Algora rejects it, refresh will continue in GitHub mode."
            }
            try updateAccountTokenFlags()
        } catch {
            authError = error.localizedDescription
        }
    }

    func clearGitHubToken() {
        do {
            try keychain.delete(.githubToken)
            hasGitHubToken = false
            isAuthenticated = false
            authenticatedLogin = nil
            syncMessage = "GitHub token removed."
            try updateAccountTokenFlags()
        } catch {
            authError = error.localizedDescription
        }
    }

    func refreshCurrentBounties(watchedOrgs: [WatchedOrg]) async {
        guard isRefreshing == false else { return }
        guard let modelContext else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard let githubToken = try keychain.read(.githubToken), githubToken.isEmpty == false else {
                syncMessage = "Add a GitHub token to sync claimed PRs."
                return
            }
            let previous = try modelContext.fetch(FetchDescriptor<Bounty>())
            let algoraToken = try keychain.read(.algoraToken)
            let orgs = watchedOrgs.filter(\.isEnabled).map(\.handle)
            let result = await service.refreshCurrentBounties(githubToken: githubToken, algoraToken: algoraToken, watchedOrgs: orgs)
            warnings = result.warnings
            if let user = result.user {
                authenticatedLogin = user.login
                isAuthenticated = true
                try upsertAccount(user: user, hasGitHubToken: true, hasAlgoraToken: algoraToken?.isEmpty == false)
            }
            try apply(result: result, previousBounties: previous)
            let count = result.bounties.count
            if count == 0 {
                syncMessage = "Refresh finished. Scanned \(result.scannedPullRequestCount) recent PRs but found no Algora-backed bounty evidence. Import a GitHub issue or PR URL if the bounty is outside your recent authored PRs."
            } else {
                syncMessage = "Refresh finished. Updated \(count) tracked bounties from \(result.scannedPullRequestCount) scanned PRs."
            }
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func discover() async {
        guard isDiscovering == false else { return }
        isDiscovering = true
        defer { isDiscovering = false }
        do {
            let token: String?
            do {
                token = try keychain.read(.githubToken)
            } catch {
                token = nil
            }
            let result = await service.discoverBounties(filters: discoverFilters, githubToken: token)
            warnings = result.warnings
            discoveredBounties = result.bounties
            syncMessage = "Found \(result.bounties.count) public bounty candidates."
        }
    }

    func trackDiscovered(_ snapshot: TrackedBountySnapshot) {
        do {
            try upsertBounty(snapshot)
            try modelContext?.save()
            syncMessage = "Added \(snapshot.repoOwner)/\(snapshot.repoName)#\(snapshot.issueNumber) to tracking."
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func addManualURL(_ text: String) -> Bool {
        guard let snapshot = service.manualSnapshot(from: text) else { return false }
        do {
            try upsertBounty(snapshot)
            try modelContext?.save()
            syncMessage = "Imported \(snapshot.repoOwner)/\(snapshot.repoName)#\(snapshot.issueNumber). Refresh to fetch live metadata."
            return true
        } catch {
            syncMessage = error.localizedDescription
            return false
        }
    }

    func clearCachedData() {
        guard let modelContext else { return }
        do {
            try deleteAll(Bounty.self)
            try deleteAll(PullRequest.self)
            try deleteAll(GitHubIssue.self)
            try deleteAll(RepoRuleSet.self)
            try deleteAll(CompetitorPR.self)
            try deleteAll(AlertEvent.self)
            try deleteAll(RiskScoreSnapshot.self)
            try deleteAll(Claim.self)
            try modelContext.save()
            discoveredBounties = []
            syncMessage = "Cached tracker data cleared. Tokens were kept in Keychain."
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    func copyToClipboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        syncMessage = "Copied."
        #endif
    }

    func markdownExport(for bounties: [Bounty]) -> String {
        var lines = ["# BountyDesk Export", "", "Generated: \(Date().formatted())", ""]
        for bounty in bounties.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            lines.append("## \(bounty.issueSlug) - \(bounty.title)")
            lines.append("- Payout: \(bounty.payoutText)")
            lines.append("- Status: \(bounty.workflowStatus.rawValue)")
            lines.append("- Claim: \(bounty.claimStatus.rawValue)")
            lines.append("- Checks: \(bounty.checkState.rawValue)")
            lines.append("- Risk: \(bounty.riskLevel.rawValue) (\(bounty.payoutChance)%)")
            lines.append("- Competition: \(bounty.competitionCount)")
            lines.append("- Next action: \(bounty.nextAction)")
            lines.append("- GitHub: \(bounty.githubIssueURLString)")
            if let pull = bounty.pullRequestURL?.absoluteString { lines.append("- PR: \(pull)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func csvExport(for bounties: [Bounty]) -> String {
        var rows = ["repo,issue,pr,title,payout,status,claim,checks,risk,payoutChance,competition,nextAction,githubURL"]
        for bounty in bounties.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let cells = [
                bounty.repoSlug,
                "\(bounty.issueNumber)",
                bounty.linkedPullRequestNumber.map { String($0) } ?? "",
                bounty.title,
                bounty.payoutText,
                bounty.workflowStatus.rawValue,
                bounty.claimStatus.rawValue,
                bounty.checkState.rawValue,
                bounty.riskLevel.rawValue,
                "\(bounty.payoutChance)",
                "\(bounty.competitionCount)",
                bounty.nextAction,
                bounty.githubIssueURLString
            ]
            rows.append(cells.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func apply(result: TrackerRefreshResult, previousBounties: [Bounty]) throws {
        let previous = Dictionary(uniqueKeysWithValues: previousBounties.map { ($0.stableID, PreviousBountyState(from: $0)) })
        for snapshot in result.bounties {
            try upsertBounty(snapshot)
            generateAlerts(for: snapshot, previous: previous[snapshot.stableID])
        }
        for snapshot in result.pullRequests { try upsertPullRequest(snapshot) }
        for snapshot in result.issues { try upsertIssue(snapshot) }
        for snapshot in result.ruleSets { try upsertRuleSet(snapshot) }
        for snapshot in result.competitors { try upsertCompetitor(snapshot) }
        for snapshot in result.claims { try upsertClaim(snapshot) }
        for snapshot in result.riskSnapshots { try insertRiskSnapshot(snapshot) }
        try modelContext?.save()
    }

    private func upsertBounty(_ snapshot: TrackedBountySnapshot) throws {
        guard let modelContext else { return }
        let key = snapshot.stableID
        var descriptor = FetchDescriptor<Bounty>(predicate: #Predicate { $0.stableID == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(Bounty(snapshot: snapshot))
        }
    }

    private func upsertPullRequest(_ snapshot: PullRequestSnapshot) throws {
        guard let modelContext else { return }
        let key = snapshot.stableID
        var descriptor = FetchDescriptor<PullRequest>(predicate: #Predicate { $0.stableID == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(PullRequest(snapshot: snapshot))
        }
    }

    private func upsertIssue(_ snapshot: GitHubIssueSnapshot) throws {
        guard let modelContext else { return }
        let key = snapshot.stableID
        var descriptor = FetchDescriptor<GitHubIssue>(predicate: #Predicate { $0.stableID == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(GitHubIssue(snapshot: snapshot))
        }
    }

    private func upsertRuleSet(_ snapshot: RepoRuleSetSnapshot) throws {
        guard let modelContext else { return }
        let key = snapshot.stableID
        var descriptor = FetchDescriptor<RepoRuleSet>(predicate: #Predicate { $0.stableID == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.bountyStableID = snapshot.bountyStableID
            existing.repoOwner = snapshot.repoOwner
            existing.repoName = snapshot.repoName
            existing.codeOfConductSummary = snapshot.codeOfConductSummary
            existing.contributingSummary = snapshot.contributingSummary
            existing.readmeSummary = snapshot.readmeSummary
            existing.testCommands = snapshot.testCommands
            existing.requiresDemoVideo = snapshot.requiresDemoVideo
            existing.assignmentRequired = snapshot.assignmentRequired
            existing.maintainerAssignmentRequired = snapshot.maintainerAssignmentRequired
            existing.repoArchived = snapshot.repoArchived
            existing.updatedAt = snapshot.updatedAt
        } else {
            modelContext.insert(RepoRuleSet(snapshot: snapshot))
        }
    }

    private func upsertCompetitor(_ snapshot: CompetitorPRSnapshot) throws {
        guard let modelContext else { return }
        let key = snapshot.stableID
        var descriptor = FetchDescriptor<CompetitorPR>(predicate: #Predicate { $0.stableID == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(snapshot)
        } else {
            modelContext.insert(CompetitorPR(snapshot: snapshot))
        }
    }

    private func upsertClaim(_ snapshot: ClaimSnapshot) throws {
        guard let modelContext else { return }
        let key = snapshot.stableID
        var descriptor = FetchDescriptor<Claim>(predicate: #Predicate { $0.stableID == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.bountyStableID = snapshot.bountyStableID
            existing.status = snapshot.status
            existing.solverLogin = snapshot.solverLogin
            existing.urlString = snapshot.urlString
            existing.transferAmount = snapshot.transferAmount
            existing.transferCurrency = snapshot.transferCurrency
            existing.updatedAt = snapshot.updatedAt
        } else {
            modelContext.insert(Claim(stableID: snapshot.stableID, bountyStableID: snapshot.bountyStableID, status: snapshot.status, solverLogin: snapshot.solverLogin, urlString: snapshot.urlString, transferAmount: snapshot.transferAmount, transferCurrency: snapshot.transferCurrency, createdAt: snapshot.createdAt, updatedAt: snapshot.updatedAt))
        }
    }

    private func insertRiskSnapshot(_ snapshot: RiskSnapshotData) throws {
        guard let modelContext else { return }
        modelContext.insert(RiskScoreSnapshot(stableID: snapshot.stableID, bountyStableID: snapshot.bountyStableID, score: snapshot.score, level: snapshot.level, factors: snapshot.factors, nextAction: snapshot.nextAction, createdAt: snapshot.createdAt))
    }

    private func upsertAccount(user: GitHubUser, hasGitHubToken: Bool, hasAlgoraToken: Bool) throws {
        guard let modelContext else { return }
        let login = user.login
        var descriptor = FetchDescriptor<UserAccount>(predicate: #Predicate { $0.githubLogin == login })
        descriptor.fetchLimit = 1
        if let account = try modelContext.fetch(descriptor).first {
            account.githubAvatarURLString = user.avatarUrl
            account.githubHTMLURLString = user.htmlUrl
            account.hasGitHubToken = hasGitHubToken
            account.hasAlgoraToken = hasAlgoraToken
            account.lastValidatedAt = Date()
            account.updatedAt = Date()
        } else {
            modelContext.insert(UserAccount(githubLogin: user.login, githubAvatarURLString: user.avatarUrl, githubHTMLURLString: user.htmlUrl, hasGitHubToken: hasGitHubToken, hasAlgoraToken: hasAlgoraToken, lastValidatedAt: Date()))
        }
        try modelContext.save()
    }

    private func updateAccountTokenFlags() throws {
        guard let modelContext else { return }
        let accounts = try modelContext.fetch(FetchDescriptor<UserAccount>())
        for account in accounts {
            account.hasGitHubToken = hasGitHubToken
            account.hasAlgoraToken = hasAlgoraToken
            account.updatedAt = Date()
        }
        try modelContext.save()
    }

    private func generateAlerts(for snapshot: TrackedBountySnapshot, previous: PreviousBountyState?) {
        guard let previous else { return }
        if previous.latestMaintainerComment != snapshot.latestMaintainerComment, snapshot.latestMaintainerComment.isEmpty == false {
            insertAlert(kind: .maintainerComment, bountyStableID: snapshot.stableID, title: "Maintainer activity on \(snapshot.repoName)#\(snapshot.issueNumber)", detail: snapshot.latestMaintainerComment)
        }
        if previous.latestBotComment != snapshot.latestBotComment, snapshot.latestBotComment.isEmpty == false {
            insertAlert(kind: .botStatus, bountyStableID: snapshot.stableID, title: "Bot status changed", detail: snapshot.latestBotComment)
        }
        if previous.checkState != .failing, snapshot.checkState == .failing {
            insertAlert(kind: .checksFailed, bountyStableID: snapshot.stableID, title: "Checks failed", detail: snapshot.nextAction)
        }
        if previous.checkState == .failing, snapshot.checkState == .passing {
            insertAlert(kind: .checksRecovered, bountyStableID: snapshot.stableID, title: "Checks recovered", detail: snapshot.nextAction)
        }
        if previous.workflowStatus != .mergedUnpaid, snapshot.workflowStatus == .mergedUnpaid {
            insertAlert(kind: .pullRequestMerged, bountyStableID: snapshot.stableID, title: "PR merged", detail: snapshot.nextAction)
        }
        if previous.workflowStatus != .lost, snapshot.workflowStatus == .lost {
            insertAlert(kind: .pullRequestClosed, bountyStableID: snapshot.stableID, title: "PR closed or lost", detail: snapshot.nextAction)
        }
        if previous.issueState != .closed, snapshot.issueState == .closed {
            insertAlert(kind: .issueClosed, bountyStableID: snapshot.stableID, title: "Issue closed", detail: snapshot.nextAction)
        }
        if previous.claimStatus != snapshot.claimStatus {
            insertAlert(kind: .claimStatusChanged, bountyStableID: snapshot.stableID, title: "Claim status: \(snapshot.claimStatus.rawValue)", detail: snapshot.nextAction)
        }
        if previous.hasRewardedSignal == false, snapshot.hasRewardedSignal {
            insertAlert(kind: .payoutStatusChanged, bountyStableID: snapshot.stableID, title: "Reward or payment signal found", detail: snapshot.nextAction)
        }
    }

    private func insertAlert(kind: AlertKind, bountyStableID: String?, title: String, detail: String) {
        guard let modelContext, shouldRecordAlert(kind) else { return }
        let snapshot = AlertSnapshot(stableID: "\(kind.rawValue):\(bountyStableID ?? "global"):\(Date().timeIntervalSinceReferenceDate)", bountyStableID: bountyStableID, kind: kind, title: title, detail: detail, isRead: false, createdAt: Date())
        modelContext.insert(AlertEvent(snapshot: snapshot))
    }

    private func shouldRecordAlert(_ kind: AlertKind) -> Bool {
        let defaults = UserDefaults.standard
        func enabled(_ key: String) -> Bool {
            defaults.object(forKey: key) as? Bool ?? true
        }
        switch kind {
        case .maintainerComment, .botStatus:
            return enabled("notifyMaintainerComments")
        case .checksFailed, .checksRecovered:
            return enabled("notifyChecks")
        case .claimStatusChanged, .payoutStatusChanged:
            return enabled("notifyPayment")
        default:
            return true
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        guard let modelContext else { return }
        for item in try modelContext.fetch(FetchDescriptor<T>()) {
            modelContext.delete(item)
        }
    }

    private func csvEscape(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

private struct PreviousBountyState {
    var workflowStatus: BountyWorkflowStatus
    var issueState: IssueState
    var claimStatus: ClaimStatus
    var checkState: CheckState
    var latestMaintainerComment: String
    var latestBotComment: String
    var hasRewardedSignal: Bool

    init(from bounty: Bounty) {
        workflowStatus = bounty.workflowStatus
        issueState = bounty.issueState
        claimStatus = bounty.claimStatus
        checkState = bounty.checkState
        latestMaintainerComment = bounty.latestMaintainerComment
        latestBotComment = bounty.latestBotComment
        hasRewardedSignal = bounty.hasRewardedSignal
    }
}
