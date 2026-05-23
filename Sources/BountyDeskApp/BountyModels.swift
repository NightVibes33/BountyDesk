import Foundation
import SwiftData

enum BountyWorkflowStatus: String, CaseIterable, Codable, Identifiable {
    case watching = "Watching"
    case claimed = "Claimed"
    case submitted = "Submitted"
    case pendingReview = "Pending Review"
    case mergedUnpaid = "Merged Unpaid"
    case paid = "Paid"
    case lost = "Closed/Lost"
    case blocked = "Blocked"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .watching: return "eye"
        case .claimed: return "flag"
        case .submitted: return "paperplane"
        case .pendingReview: return "text.badge.checkmark"
        case .mergedUnpaid: return "arrow.triangle.merge"
        case .paid: return "banknote"
        case .lost: return "xmark.circle"
        case .blocked: return "exclamationmark.triangle"
        }
    }
}

enum BountySource: String, CaseIterable, Codable, Identifiable {
    case github = "GitHub"
    case algoraPublic = "Algora Public"
    case algoraAuthenticated = "Algora API"
    case manual = "Manual"
    case mock = "Mock"

    var id: String { rawValue }
}

enum PullRequestState: String, CaseIterable, Codable, Identifiable {
    case open = "Open"
    case draft = "Draft"
    case merged = "Merged"
    case closed = "Closed"
    case unknown = "Unknown"

    var id: String { rawValue }
}

enum IssueState: String, CaseIterable, Codable, Identifiable {
    case open = "Open"
    case closed = "Closed"
    case unknown = "Unknown"

    var id: String { rawValue }
}

enum ClaimStatus: String, CaseIterable, Codable, Identifiable {
    case unknown = "Unknown"
    case pending = "Pending"
    case accepted = "Accepted"
    case paymentProcessing = "Payment Processing"
    case paymentSucceeded = "Payment Succeeded"
    case rejected = "Rejected"

    var id: String { rawValue }
}

enum CheckState: String, CaseIterable, Codable, Identifiable {
    case passing = "Passing"
    case failing = "Failing"
    case pending = "Pending"
    case noneConfigured = "None Configured"
    case unknown = "Unknown"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .passing: return "checkmark.circle"
        case .failing: return "xmark.octagon"
        case .pending: return "clock"
        case .noneConfigured: return "minus.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

enum RiskLevel: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }
}


enum BountyManagementStage: String, CaseIterable, Codable, Identifiable {
    case inbox = "Inbox"
    case focus = "Focus"
    case waiting = "Waiting"
    case payout = "Payout"
    case done = "Done"
    case archived = "Archived"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .focus: return "scope"
        case .waiting: return "clock"
        case .payout: return "banknote"
        case .done: return "checkmark.seal"
        case .archived: return "archivebox"
        }
    }
}

enum BountyUserPriority: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"
    case urgent = "Urgent"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .normal: return "equal.circle"
        case .high: return "arrow.up.circle"
        case .urgent: return "exclamationmark.circle"
        }
    }
}

enum AlertKind: String, CaseIterable, Codable, Identifiable {
    case maintainerComment = "Maintainer Comment"
    case botStatus = "Bot Status"
    case checksFailed = "Checks Failed"
    case checksRecovered = "Checks Recovered"
    case pullRequestMerged = "PR Merged"
    case pullRequestClosed = "PR Closed"
    case issueClosed = "Issue Closed"
    case claimStatusChanged = "Claim Status Changed"
    case competitorMerged = "Competitor Merged"
    case payoutStatusChanged = "Payout Status Changed"
    case warning = "Warning"

    var id: String { rawValue }
}

@Model
final class UserAccount {
    @Attribute(.unique) var id: UUID
    var githubLogin: String
    var githubAvatarURLString: String?
    var githubHTMLURLString: String?
    var hasGitHubToken: Bool
    var hasAlgoraToken: Bool
    var lastValidatedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        githubLogin: String,
        githubAvatarURLString: String? = nil,
        githubHTMLURLString: String? = nil,
        hasGitHubToken: Bool = false,
        hasAlgoraToken: Bool = false,
        lastValidatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.githubLogin = githubLogin
        self.githubAvatarURLString = githubAvatarURLString
        self.githubHTMLURLString = githubHTMLURLString
        self.hasGitHubToken = hasGitHubToken
        self.hasAlgoraToken = hasAlgoraToken
        self.lastValidatedAt = lastValidatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class WatchedOrg {
    @Attribute(.unique) var handle: String
    var displayName: String
    var isEnabled: Bool
    var createdAt: Date

    init(handle: String, displayName: String? = nil, isEnabled: Bool = true, createdAt: Date = Date()) {
        self.handle = handle
        self.displayName = displayName ?? handle
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

@Model
final class Bounty {
    @Attribute(.unique) var stableID: String
    var id: UUID
    var sourceRaw: String
    var repoOwner: String
    var repoName: String
    var issueNumber: Int
    var linkedPullRequestNumber: Int?
    var title: String
    var issueBodySummary: String
    var pullRequestSummary: String
    var amount: Int
    var currency: String
    var labelsText: String
    var algoraEvidenceText: String
    var rewardLinksText: String
    var workflowStatusRaw: String
    var issueStateRaw: String
    var claimStatusRaw: String
    var checkStateRaw: String
    var riskLevelRaw: String
    var payoutChance: Int
    var riskFactorsText: String
    var nextAction: String
    var latestMaintainerComment: String
    var latestBotComment: String
    var competitionCount: Int
    var hasRewardedSignal: Bool
    var requiresVideo: Bool
    var hasDemoProof: Bool
    var repoArchived: Bool
    var assignedOnly: Bool
    var userAppearsAssigned: Bool
    var maintainerAssignmentRequired: Bool
    var priorRejectedSignal: Bool
    var hasClearVerification: Bool
    var hasTests: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastRefreshedAt: Date?
    var managementStageRaw: String?
    var userPriorityRaw: String?
    var isPinned: Bool = false
    var followUpAt: Date?
    var userNotes: String = ""
    var userTagsText: String = ""
    var lastManagedAt: Date?

    init(snapshot: TrackedBountySnapshot) {
        self.stableID = snapshot.stableID
        self.id = snapshot.id
        self.sourceRaw = snapshot.source.rawValue
        self.repoOwner = snapshot.repoOwner
        self.repoName = snapshot.repoName
        self.issueNumber = snapshot.issueNumber
        self.linkedPullRequestNumber = snapshot.linkedPullRequestNumber
        self.title = snapshot.title
        self.issueBodySummary = snapshot.issueBodySummary
        self.pullRequestSummary = snapshot.pullRequestSummary
        self.amount = snapshot.amount
        self.currency = snapshot.currency
        self.labelsText = LineCodec.encode(snapshot.labels)
        self.algoraEvidenceText = LineCodec.encode(snapshot.algoraEvidence)
        self.rewardLinksText = LineCodec.encode(snapshot.rewardLinks)
        self.workflowStatusRaw = snapshot.workflowStatus.rawValue
        self.issueStateRaw = snapshot.issueState.rawValue
        self.claimStatusRaw = snapshot.claimStatus.rawValue
        self.checkStateRaw = snapshot.checkState.rawValue
        self.riskLevelRaw = snapshot.riskLevel.rawValue
        self.payoutChance = snapshot.payoutChance
        self.riskFactorsText = LineCodec.encode(snapshot.riskFactors)
        self.nextAction = snapshot.nextAction
        self.latestMaintainerComment = snapshot.latestMaintainerComment
        self.latestBotComment = snapshot.latestBotComment
        self.competitionCount = snapshot.competitionCount
        self.hasRewardedSignal = snapshot.hasRewardedSignal
        self.requiresVideo = snapshot.requiresVideo
        self.hasDemoProof = snapshot.hasDemoProof
        self.repoArchived = snapshot.repoArchived
        self.assignedOnly = snapshot.assignedOnly
        self.userAppearsAssigned = snapshot.userAppearsAssigned
        self.maintainerAssignmentRequired = snapshot.maintainerAssignmentRequired
        self.priorRejectedSignal = snapshot.priorRejectedSignal
        self.hasClearVerification = snapshot.hasClearVerification
        self.hasTests = snapshot.hasTests
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
        self.lastRefreshedAt = snapshot.lastRefreshedAt
        self.managementStageRaw = nil
        self.userPriorityRaw = nil
        self.isPinned = false
        self.followUpAt = nil
        self.userNotes = ""
        self.userTagsText = ""
        self.lastManagedAt = nil
    }

    func apply(_ snapshot: TrackedBountySnapshot) {
        source = snapshot.source
        repoOwner = snapshot.repoOwner
        repoName = snapshot.repoName
        issueNumber = snapshot.issueNumber
        linkedPullRequestNumber = snapshot.linkedPullRequestNumber
        title = snapshot.title
        issueBodySummary = snapshot.issueBodySummary
        pullRequestSummary = snapshot.pullRequestSummary
        amount = snapshot.amount
        currency = snapshot.currency
        labels = snapshot.labels
        algoraEvidence = snapshot.algoraEvidence
        rewardLinks = snapshot.rewardLinks
        workflowStatus = snapshot.workflowStatus
        issueState = snapshot.issueState
        claimStatus = snapshot.claimStatus
        checkState = snapshot.checkState
        riskLevel = snapshot.riskLevel
        payoutChance = snapshot.payoutChance
        riskFactors = snapshot.riskFactors
        nextAction = snapshot.nextAction
        latestMaintainerComment = snapshot.latestMaintainerComment
        latestBotComment = snapshot.latestBotComment
        competitionCount = snapshot.competitionCount
        hasRewardedSignal = snapshot.hasRewardedSignal
        requiresVideo = snapshot.requiresVideo
        hasDemoProof = snapshot.hasDemoProof
        repoArchived = snapshot.repoArchived
        assignedOnly = snapshot.assignedOnly
        userAppearsAssigned = snapshot.userAppearsAssigned
        maintainerAssignmentRequired = snapshot.maintainerAssignmentRequired
        priorRejectedSignal = snapshot.priorRejectedSignal
        hasClearVerification = snapshot.hasClearVerification
        hasTests = snapshot.hasTests
        updatedAt = snapshot.updatedAt
        lastRefreshedAt = snapshot.lastRefreshedAt
    }

    var source: BountySource {
        get { BountySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var workflowStatus: BountyWorkflowStatus {
        get { BountyWorkflowStatus(rawValue: workflowStatusRaw) ?? .watching }
        set { workflowStatusRaw = newValue.rawValue }
    }

    var issueState: IssueState {
        get { IssueState(rawValue: issueStateRaw) ?? .unknown }
        set { issueStateRaw = newValue.rawValue }
    }

    var claimStatus: ClaimStatus {
        get { ClaimStatus(rawValue: claimStatusRaw) ?? .unknown }
        set { claimStatusRaw = newValue.rawValue }
    }

    var checkState: CheckState {
        get { CheckState(rawValue: checkStateRaw) ?? .unknown }
        set { checkStateRaw = newValue.rawValue }
    }

    var riskLevel: RiskLevel {
        get { RiskLevel(rawValue: riskLevelRaw) ?? .medium }
        set { riskLevelRaw = newValue.rawValue }
    }

    var labels: [String] {
        get { LineCodec.decode(labelsText) }
        set { labelsText = LineCodec.encode(newValue) }
    }

    var algoraEvidence: [String] {
        get { LineCodec.decode(algoraEvidenceText) }
        set { algoraEvidenceText = LineCodec.encode(newValue) }
    }

    var rewardLinks: [String] {
        get { LineCodec.decode(rewardLinksText) }
        set { rewardLinksText = LineCodec.encode(newValue) }
    }

    var riskFactors: [String] {
        get { LineCodec.decode(riskFactorsText) }
        set { riskFactorsText = LineCodec.encode(newValue) }
    }

    var managementStage: BountyManagementStage {
        get {
            if let managementStageRaw, let stage = BountyManagementStage(rawValue: managementStageRaw) { return stage }
            return suggestedManagementStage
        }
        set {
            managementStageRaw = newValue.rawValue
            lastManagedAt = Date()
        }
    }

    var userPriority: BountyUserPriority {
        get {
            if let userPriorityRaw, let priority = BountyUserPriority(rawValue: userPriorityRaw) { return priority }
            return suggestedPriority
        }
        set {
            userPriorityRaw = newValue.rawValue
            lastManagedAt = Date()
        }
    }

    var userTags: [String] {
        get { LineCodec.decode(userTagsText) }
        set {
            userTagsText = LineCodec.encode(newValue)
            lastManagedAt = Date()
        }
    }

    var isArchived: Bool { managementStage == .archived }
    var isFollowUpDue: Bool { followUpAt.map { $0 <= Date() } ?? false }
    var hasFollowUp: Bool { followUpAt != nil }

    var managementSummary: String {
        if isFollowUpDue { return "Follow up is due" }
        if let followUpAt { return "Follow up \(followUpAt.formatted(date: .abbreviated, time: .omitted))" }
        if userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return "Notes saved" }
        return managementStage == suggestedManagementStage ? "Auto-sorted from live status" : "Managed manually"
    }

    private var suggestedManagementStage: BountyManagementStage {
        if workflowStatus == .paid || claimStatus == .paymentSucceeded { return .done }
        if workflowStatus == .lost || workflowStatus == .blocked { return .archived }
        if workflowStatus == .mergedUnpaid || claimStatus == .paymentProcessing || claimStatus == .accepted { return .payout }
        if workflowStatus == .pendingReview || latestMaintainerComment.isEmpty == false { return .waiting }
        if checkState == .failing || riskLevel == .high || priorRejectedSignal { return .focus }
        return .inbox
    }

    private var suggestedPriority: BountyUserPriority {
        if checkState == .failing || riskLevel == .high || priorRejectedSignal { return .urgent }
        if amount >= 500 || workflowStatus == .mergedUnpaid || claimStatus == .paymentProcessing { return .high }
        if riskLevel == .low && amount < 100 { return .low }
        return .normal
    }

    var repoSlug: String { "\(repoOwner)/\(repoName)" }
    var issueSlug: String { "\(repoSlug)#\(issueNumber)" }
    var githubIssueURLString: String { "https://github.com/\(repoOwner)/\(repoName)/issues/\(issueNumber)" }
    var algoraIssueURLString: String { "https://algora.io/\(repoOwner)/\(repoName)/issues/\(issueNumber)" }
    var githubIssueURL: URL { URL(string: githubIssueURLString)! }
    var algoraIssueURL: URL { URL(string: algoraIssueURLString)! }
    var pullRequestURL: URL? {
        guard let linkedPullRequestNumber else { return nil }
        return URL(string: "https://github.com/\(repoOwner)/\(repoName)/pull/\(linkedPullRequestNumber)")
    }

    var payoutText: String {
        guard amount > 0 else { return "TBD" }
        return amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}

@Model
final class Claim {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String
    var statusRaw: String
    var solverLogin: String?
    var urlString: String?
    var transferAmount: Int
    var transferCurrency: String
    var createdAt: Date
    var updatedAt: Date

    init(stableID: String, bountyStableID: String, status: ClaimStatus, solverLogin: String? = nil, urlString: String? = nil, transferAmount: Int = 0, transferCurrency: String = "USD", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.stableID = stableID
        self.bountyStableID = bountyStableID
        self.statusRaw = status.rawValue
        self.solverLogin = solverLogin
        self.urlString = urlString
        self.transferAmount = transferAmount
        self.transferCurrency = transferCurrency
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: ClaimStatus {
        get { ClaimStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class PullRequest {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String
    var repoOwner: String
    var repoName: String
    var number: Int
    var title: String
    var authorLogin: String
    var bodySummary: String
    var htmlURLString: String
    var stateRaw: String
    var isDraft: Bool
    var mergeableState: String
    var headSHA: String?
    var labelsText: String
    var checkStateRaw: String
    var latestComment: String
    var latestMaintainerComment: String
    var changedFiles: Int
    var additions: Int
    var deletions: Int
    var hasDemoProof: Bool
    var hasTests: Bool
    var updatedAt: Date

    init(snapshot: PullRequestSnapshot) {
        stableID = snapshot.stableID
        bountyStableID = snapshot.bountyStableID
        repoOwner = snapshot.repoOwner
        repoName = snapshot.repoName
        number = snapshot.number
        title = snapshot.title
        authorLogin = snapshot.authorLogin
        bodySummary = snapshot.bodySummary
        htmlURLString = snapshot.htmlURLString
        stateRaw = snapshot.state.rawValue
        isDraft = snapshot.isDraft
        mergeableState = snapshot.mergeableState
        headSHA = snapshot.headSHA
        labelsText = LineCodec.encode(snapshot.labels)
        checkStateRaw = snapshot.checkState.rawValue
        latestComment = snapshot.latestComment
        latestMaintainerComment = snapshot.latestMaintainerComment
        changedFiles = snapshot.changedFiles
        additions = snapshot.additions
        deletions = snapshot.deletions
        hasDemoProof = snapshot.hasDemoProof
        hasTests = snapshot.hasTests
        updatedAt = snapshot.updatedAt
    }

    func apply(_ snapshot: PullRequestSnapshot) {
        bountyStableID = snapshot.bountyStableID
        repoOwner = snapshot.repoOwner
        repoName = snapshot.repoName
        number = snapshot.number
        title = snapshot.title
        authorLogin = snapshot.authorLogin
        bodySummary = snapshot.bodySummary
        htmlURLString = snapshot.htmlURLString
        state = snapshot.state
        isDraft = snapshot.isDraft
        mergeableState = snapshot.mergeableState
        headSHA = snapshot.headSHA
        labels = snapshot.labels
        checkState = snapshot.checkState
        latestComment = snapshot.latestComment
        latestMaintainerComment = snapshot.latestMaintainerComment
        changedFiles = snapshot.changedFiles
        additions = snapshot.additions
        deletions = snapshot.deletions
        hasDemoProof = snapshot.hasDemoProof
        hasTests = snapshot.hasTests
        updatedAt = snapshot.updatedAt
    }

    var state: PullRequestState {
        get { PullRequestState(rawValue: stateRaw) ?? .unknown }
        set { stateRaw = newValue.rawValue }
    }

    var checkState: CheckState {
        get { CheckState(rawValue: checkStateRaw) ?? .unknown }
        set { checkStateRaw = newValue.rawValue }
    }

    var labels: [String] {
        get { LineCodec.decode(labelsText) }
        set { labelsText = LineCodec.encode(newValue) }
    }

    var htmlURL: URL? { URL(string: htmlURLString) }
}

@Model
final class GitHubIssue {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String
    var repoOwner: String
    var repoName: String
    var number: Int
    var title: String
    var bodySummary: String
    var htmlURLString: String
    var stateRaw: String
    var labelsText: String
    var latestComment: String
    var latestBotComment: String
    var hasAlgoraEvidence: Bool
    var bountyAmount: Int
    var requiresVideo: Bool
    var hasRewardedSignal: Bool
    var updatedAt: Date

    init(snapshot: GitHubIssueSnapshot) {
        stableID = snapshot.stableID
        bountyStableID = snapshot.bountyStableID
        repoOwner = snapshot.repoOwner
        repoName = snapshot.repoName
        number = snapshot.number
        title = snapshot.title
        bodySummary = snapshot.bodySummary
        htmlURLString = snapshot.htmlURLString
        stateRaw = snapshot.state.rawValue
        labelsText = LineCodec.encode(snapshot.labels)
        latestComment = snapshot.latestComment
        latestBotComment = snapshot.latestBotComment
        hasAlgoraEvidence = snapshot.hasAlgoraEvidence
        bountyAmount = snapshot.bountyAmount
        requiresVideo = snapshot.requiresVideo
        hasRewardedSignal = snapshot.hasRewardedSignal
        updatedAt = snapshot.updatedAt
    }

    func apply(_ snapshot: GitHubIssueSnapshot) {
        bountyStableID = snapshot.bountyStableID
        repoOwner = snapshot.repoOwner
        repoName = snapshot.repoName
        number = snapshot.number
        title = snapshot.title
        bodySummary = snapshot.bodySummary
        htmlURLString = snapshot.htmlURLString
        state = snapshot.state
        labels = snapshot.labels
        latestComment = snapshot.latestComment
        latestBotComment = snapshot.latestBotComment
        hasAlgoraEvidence = snapshot.hasAlgoraEvidence
        bountyAmount = snapshot.bountyAmount
        requiresVideo = snapshot.requiresVideo
        hasRewardedSignal = snapshot.hasRewardedSignal
        updatedAt = snapshot.updatedAt
    }

    var state: IssueState {
        get { IssueState(rawValue: stateRaw) ?? .unknown }
        set { stateRaw = newValue.rawValue }
    }

    var labels: [String] {
        get { LineCodec.decode(labelsText) }
        set { labelsText = LineCodec.encode(newValue) }
    }
}

@Model
final class RepoRuleSet {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String
    var repoOwner: String
    var repoName: String
    var codeOfConductSummary: String
    var contributingSummary: String
    var readmeSummary: String
    var testCommandsText: String
    var requiresDemoVideo: Bool
    var assignmentRequired: Bool
    var maintainerAssignmentRequired: Bool
    var repoArchived: Bool
    var updatedAt: Date

    init(snapshot: RepoRuleSetSnapshot) {
        stableID = snapshot.stableID
        bountyStableID = snapshot.bountyStableID
        repoOwner = snapshot.repoOwner
        repoName = snapshot.repoName
        codeOfConductSummary = snapshot.codeOfConductSummary
        contributingSummary = snapshot.contributingSummary
        readmeSummary = snapshot.readmeSummary
        testCommandsText = LineCodec.encode(snapshot.testCommands)
        requiresDemoVideo = snapshot.requiresDemoVideo
        assignmentRequired = snapshot.assignmentRequired
        maintainerAssignmentRequired = snapshot.maintainerAssignmentRequired
        repoArchived = snapshot.repoArchived
        updatedAt = snapshot.updatedAt
    }

    var testCommands: [String] {
        get { LineCodec.decode(testCommandsText) }
        set { testCommandsText = LineCodec.encode(newValue) }
    }
}

@Model
final class CompetitorPR {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String
    var number: Int
    var authorLogin: String
    var title: String
    var htmlURLString: String
    var stateRaw: String
    var checkStateRaw: String
    var changedFiles: Int
    var additions: Int
    var deletions: Int
    var labelsText: String
    var latestComment: String
    var hasDemoProof: Bool
    var hasMaintainerApproval: Bool
    var updatedAt: Date

    init(snapshot: CompetitorPRSnapshot) {
        stableID = snapshot.stableID
        bountyStableID = snapshot.bountyStableID
        number = snapshot.number
        authorLogin = snapshot.authorLogin
        title = snapshot.title
        htmlURLString = snapshot.htmlURLString
        stateRaw = snapshot.state.rawValue
        checkStateRaw = snapshot.checkState.rawValue
        changedFiles = snapshot.changedFiles
        additions = snapshot.additions
        deletions = snapshot.deletions
        labelsText = LineCodec.encode(snapshot.labels)
        latestComment = snapshot.latestComment
        hasDemoProof = snapshot.hasDemoProof
        hasMaintainerApproval = snapshot.hasMaintainerApproval
        updatedAt = snapshot.updatedAt
    }

    func apply(_ snapshot: CompetitorPRSnapshot) {
        bountyStableID = snapshot.bountyStableID
        number = snapshot.number
        authorLogin = snapshot.authorLogin
        title = snapshot.title
        htmlURLString = snapshot.htmlURLString
        state = snapshot.state
        checkState = snapshot.checkState
        changedFiles = snapshot.changedFiles
        additions = snapshot.additions
        deletions = snapshot.deletions
        labels = snapshot.labels
        latestComment = snapshot.latestComment
        hasDemoProof = snapshot.hasDemoProof
        hasMaintainerApproval = snapshot.hasMaintainerApproval
        updatedAt = snapshot.updatedAt
    }

    var state: PullRequestState {
        get { PullRequestState(rawValue: stateRaw) ?? .unknown }
        set { stateRaw = newValue.rawValue }
    }

    var checkState: CheckState {
        get { CheckState(rawValue: checkStateRaw) ?? .unknown }
        set { checkStateRaw = newValue.rawValue }
    }

    var labels: [String] {
        get { LineCodec.decode(labelsText) }
        set { labelsText = LineCodec.encode(newValue) }
    }
}

@Model
final class AlertEvent {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String?
    var kindRaw: String
    var title: String
    var detail: String
    var isRead: Bool
    var createdAt: Date

    init(snapshot: AlertSnapshot) {
        stableID = snapshot.stableID
        bountyStableID = snapshot.bountyStableID
        kindRaw = snapshot.kind.rawValue
        title = snapshot.title
        detail = snapshot.detail
        isRead = snapshot.isRead
        createdAt = snapshot.createdAt
    }

    var kind: AlertKind {
        get { AlertKind(rawValue: kindRaw) ?? .warning }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class BountyChecklistItem {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String
    var title: String
    var isDone: Bool
    var createdAt: Date
    var completedAt: Date?
    var sortIndex: Int

    init(
        stableID: String = UUID().uuidString,
        bountyStableID: String,
        title: String,
        isDone: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        sortIndex: Int = 0
    ) {
        self.stableID = stableID
        self.bountyStableID = bountyStableID
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sortIndex = sortIndex
    }

    func toggleDone() {
        isDone.toggle()
        completedAt = isDone ? Date() : nil
    }
}

@Model
final class RiskScoreSnapshot {
    @Attribute(.unique) var stableID: String
    var bountyStableID: String
    var score: Int
    var levelRaw: String
    var factorsText: String
    var nextAction: String
    var createdAt: Date

    init(stableID: String = UUID().uuidString, bountyStableID: String, score: Int, level: RiskLevel, factors: [String], nextAction: String, createdAt: Date = Date()) {
        self.stableID = stableID
        self.bountyStableID = bountyStableID
        self.score = score
        self.levelRaw = level.rawValue
        self.factorsText = LineCodec.encode(factors)
        self.nextAction = nextAction
        self.createdAt = createdAt
    }

    var level: RiskLevel {
        get { RiskLevel(rawValue: levelRaw) ?? .medium }
        set { levelRaw = newValue.rawValue }
    }

    var factors: [String] {
        get { LineCodec.decode(factorsText) }
        set { factorsText = LineCodec.encode(newValue) }
    }
}

struct TrackedBountySnapshot: Equatable {
    var stableID: String
    var id = UUID()
    var source: BountySource
    var repoOwner: String
    var repoName: String
    var issueNumber: Int
    var linkedPullRequestNumber: Int?
    var title: String
    var issueBodySummary: String
    var pullRequestSummary: String
    var amount: Int
    var currency = "USD"
    var labels: [String]
    var algoraEvidence: [String]
    var rewardLinks: [String]
    var workflowStatus: BountyWorkflowStatus
    var issueState: IssueState
    var claimStatus: ClaimStatus
    var checkState: CheckState
    var riskLevel: RiskLevel
    var payoutChance: Int
    var riskFactors: [String]
    var nextAction: String
    var latestMaintainerComment: String
    var latestBotComment: String
    var competitionCount: Int
    var hasRewardedSignal: Bool
    var requiresVideo: Bool
    var hasDemoProof: Bool
    var repoArchived: Bool
    var assignedOnly: Bool
    var userAppearsAssigned: Bool
    var maintainerAssignmentRequired: Bool
    var priorRejectedSignal: Bool
    var hasClearVerification: Bool
    var hasTests: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastRefreshedAt: Date?
}

struct PullRequestSnapshot: Equatable {
    var stableID: String
    var bountyStableID: String
    var repoOwner: String
    var repoName: String
    var number: Int
    var title: String
    var authorLogin: String
    var bodySummary: String
    var htmlURLString: String
    var state: PullRequestState
    var isDraft: Bool
    var mergeableState: String
    var headSHA: String?
    var labels: [String]
    var checkState: CheckState
    var latestComment: String
    var latestMaintainerComment: String
    var changedFiles: Int
    var additions: Int
    var deletions: Int
    var hasDemoProof: Bool
    var hasTests: Bool
    var updatedAt: Date
}

struct GitHubIssueSnapshot: Equatable {
    var stableID: String
    var bountyStableID: String
    var repoOwner: String
    var repoName: String
    var number: Int
    var title: String
    var bodySummary: String
    var htmlURLString: String
    var state: IssueState
    var labels: [String]
    var latestComment: String
    var latestBotComment: String
    var hasAlgoraEvidence: Bool
    var bountyAmount: Int
    var requiresVideo: Bool
    var hasRewardedSignal: Bool
    var updatedAt: Date
}

struct RepoRuleSetSnapshot: Equatable {
    var stableID: String
    var bountyStableID: String
    var repoOwner: String
    var repoName: String
    var codeOfConductSummary: String
    var contributingSummary: String
    var readmeSummary: String
    var testCommands: [String]
    var requiresDemoVideo: Bool
    var assignmentRequired: Bool
    var maintainerAssignmentRequired: Bool
    var repoArchived: Bool
    var updatedAt: Date
}

struct CompetitorPRSnapshot: Equatable {
    var stableID: String
    var bountyStableID: String
    var number: Int
    var authorLogin: String
    var title: String
    var htmlURLString: String
    var state: PullRequestState
    var checkState: CheckState
    var changedFiles: Int
    var additions: Int
    var deletions: Int
    var labels: [String]
    var latestComment: String
    var hasDemoProof: Bool
    var hasMaintainerApproval: Bool
    var updatedAt: Date
}


struct ClaimSnapshot: Equatable {
    var stableID: String
    var bountyStableID: String
    var status: ClaimStatus
    var solverLogin: String?
    var urlString: String?
    var transferAmount: Int
    var transferCurrency: String
    var createdAt: Date
    var updatedAt: Date
}

struct RiskSnapshotData: Equatable {
    var stableID: String
    var bountyStableID: String
    var score: Int
    var level: RiskLevel
    var factors: [String]
    var nextAction: String
    var createdAt: Date
}

struct AlertSnapshot: Equatable {
    var stableID: String
    var bountyStableID: String?
    var kind: AlertKind
    var title: String
    var detail: String
    var isRead: Bool
    var createdAt: Date
}

enum LineCodec {
    static func encode(_ values: [String]) -> String {
        values
            .map { $0.replacingOccurrences(of: "\n", with: "\\n") }
            .joined(separator: "\n")
    }

    static func decode(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).replacingOccurrences(of: "\\n", with: "\n") }
    }
}
