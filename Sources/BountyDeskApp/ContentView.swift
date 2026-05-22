import SwiftData
import SwiftUI

private let apiAccessHelpText = """
BountyDesk works best with GitHub login. Most users do not need an Algora API token.

GitHub access lets the app find your claimed PRs, linked bounty issues, checks, comments, labels, and competition.

Algora API token support is optional. Algora's docs mention Bearer-token API endpoints, but normal solver accounts may not show an API key page. If you do not see API keys in Algora, continue without one.

If you own or manage an Algora workspace, check workspace settings for API keys or contact Algora support.
"""

private let algoraSupportMessage = """
Hi Algora team, I'm building/using a bounty tracking app and would like API access for my workspace. I need read access to bounties and claims so I can query bounty status, claim status, and payment status programmatically. Can you enable API token access for my account/workspace?
"""

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \WatchedOrg.handle) private var watchedOrgs: [WatchedOrg]
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var bounties: [Bounty]
    @State private var didRestore = false

    var body: some View {
        Group {
            if app.isAuthenticated {
                MainTabs()
            } else {
                LoginView()
            }
        }
        .task {
            guard didRestore == false else { return }
            didRestore = true
            app.configure(modelContext: modelContext)
            await app.restoreSession()
        }
        .onChange(of: app.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated, bounties.isEmpty else { return }
            Task { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
        }
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "rectangle.grid.2x2") }
            BountyListView()
                .tabItem { Label("Bounties", systemImage: "tray.full") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
            AlertsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct LoginView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @State private var githubToken = ""
    @State private var algoraToken = ""
    @State private var showOAuthNote = false

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
                    Button {
                        showOAuthNote = true
                    } label: {
                        Label("Continue with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    if showOAuthNote {
                        Text("GitHub OAuth needs a backend token exchange, so this build uses personal access token entry as the reliable path and never embeds a client secret.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    SecureField("GitHub personal access token", text: $githubToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use GitHub Token") {
                        Task { await app.saveGitHubToken(githubToken) }
                    }
                    .disabled(githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Optional Algora API Token") {
                    SecureField("Algora API token", text: $algoraToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Optional Algora Token") {
                        app.saveAlgoraToken(algoraToken)
                    }
                    Text("A GitHub token is not an Algora API token. Continue without this unless your Algora workspace exposes API keys.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("API Access Help") {
                    Text(apiAccessHelpText)
                        .font(.footnote)
                    Button {
                        app.copyToClipboard(algoraSupportMessage)
                    } label: {
                        Label("Copy Algora Support Message", systemImage: "doc.on.doc")
                    }
                }

                if let error = app.authError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("BountyDesk")
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \WatchedOrg.handle) private var watchedOrgs: [WatchedOrg]
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var bounties: [Bounty]
    @Query(sort: \AlertEvent.createdAt, order: .reverse) private var alerts: [AlertEvent]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeBounties: [Bounty] {
        bounties.filter { ![BountyWorkflowStatus.paid, .lost, .blocked].contains($0.workflowStatus) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let syncMessage = app.syncMessage {
                    SyncBanner(message: syncMessage, warnings: app.warnings)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                Section("Overview") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricTile(title: "Active Potential", value: totalActiveValue, systemImage: "dollarsign.circle")
                        MetricTile(title: "Claimed PRs", value: "\(activeClaimedPRCount)", systemImage: "flag")
                        MetricTile(title: "Pending Review", value: "\(pendingReviewCount)", systemImage: "text.badge.checkmark")
                        MetricTile(title: "Merged Unpaid", value: "\(mergedUnpaidCount)", systemImage: "arrow.triangle.merge")
                        MetricTile(title: "Closed/Lost", value: "\(lostCount)", systemImage: "xmark.circle")
                        MetricTile(title: "Checks Failing", value: "\(failingChecksCount)", systemImage: "xmark.octagon")
                    }
                    .padding(.vertical, 8)
                }

                Section("Highest Priority Next Actions") {
                    if priorityActions.isEmpty {
                        ContentUnavailableView("No Actions", systemImage: "checkmark.seal", description: Text("Refresh after signing in to build your current bounty tracker."))
                    } else {
                        ForEach(priorityActions, id: \.stableID) { bounty in
                            NavigationLink {
                                BountyDetailView(bounty: bounty)
                            } label: {
                                ActionRow(bounty: bounty)
                            }
                        }
                    }
                }

                Section("Likely To Pay Soon") {
                    ForEach(likelyToPaySoon, id: \.stableID) { bounty in
                        BountyCompactRow(bounty: bounty)
                    }
                    if likelyToPaySoon.isEmpty {
                        Text("No accepted, processing, or merged-unpaid bounties yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("At Risk") {
                    ForEach(atRisk, id: \.stableID) { bounty in
                        BountyCompactRow(bounty: bounty)
                    }
                    if atRisk.isEmpty {
                        Text("No high-risk tracked bounties.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Latest Maintainer Comments") {
                    ForEach(latestMaintainerComments, id: \.stableID) { bounty in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                            Text(bounty.latestMaintainerComment).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if latestMaintainerComments.isEmpty {
                        Text("No maintainer comments detected yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("BountyDesk")
            .refreshable { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
                    } label: {
                        Image(systemName: app.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                    }
                    .disabled(app.isRefreshing)
                    .accessibilityLabel("Refresh bounties")
                }
            }
        }
    }

    private var totalActiveValue: String {
        activeBounties.reduce(0) { $0 + $1.amount }.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private var activeClaimedPRCount: Int { activeBounties.filter { $0.linkedPullRequestNumber != nil }.count }
    private var pendingReviewCount: Int { bounties.filter { $0.workflowStatus == .pendingReview }.count }
    private var mergedUnpaidCount: Int { bounties.filter { $0.workflowStatus == .mergedUnpaid }.count }
    private var lostCount: Int { bounties.filter { $0.workflowStatus == .lost }.count }
    private var failingChecksCount: Int { bounties.filter { $0.checkState == .failing }.count }

    private var priorityActions: [Bounty] {
        activeBounties.sorted { lhs, rhs in
            if lhs.riskLevel == rhs.riskLevel { return lhs.amount > rhs.amount }
            return riskRank(lhs.riskLevel) > riskRank(rhs.riskLevel)
        }.prefix(6).map { $0 }
    }

    private var likelyToPaySoon: [Bounty] {
        bounties.filter { bounty in
            bounty.claimStatus == .accepted || bounty.claimStatus == .paymentProcessing || bounty.workflowStatus == .mergedUnpaid
        }.prefix(5).map { $0 }
    }

    private var atRisk: [Bounty] {
        bounties.filter { $0.riskLevel == .high || $0.checkState == .failing || $0.repoArchived || $0.hasRewardedSignal }.prefix(5).map { $0 }
    }

    private var latestMaintainerComments: [Bounty] {
        bounties.filter { $0.latestMaintainerComment.isEmpty == false }.prefix(5).map { $0 }
    }
}

private struct BountyListView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \WatchedOrg.handle) private var watchedOrgs: [WatchedOrg]
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var bounties: [Bounty]
    @State private var searchText = ""
    @State private var selectedStatus: BountyWorkflowStatus?
    @State private var selectedRisk: RiskLevel?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filters
                }
                if filteredBounties.isEmpty {
                    ContentUnavailableView("No Bounties", systemImage: "tray", description: Text("Sync GitHub claims, discover public bounties, or import a URL."))
                } else {
                    ForEach(filteredBounties, id: \.stableID) { bounty in
                        NavigationLink {
                            BountyDetailView(bounty: bounty)
                        } label: {
                            BountyRow(bounty: bounty)
                        }
                        .contextMenu {
                            Link("Open GitHub Issue", destination: bounty.githubIssueURL)
                            Link("Open Algora Page", destination: bounty.algoraIssueURL)
                            if let url = bounty.pullRequestURL { Link("Open Pull Request", destination: url) }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Repo, title, label, next action")
            .navigationTitle("Current Bounties")
            .refreshable { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import bounty URL")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(app.isRefreshing)
                        .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $isAdding) { AddBountyView() }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Status", selection: Binding(get: { selectedStatus }, set: { selectedStatus = $0 })) {
                Text("All").tag(nil as BountyWorkflowStatus?)
                ForEach(BountyWorkflowStatus.allCases) { status in Text(status.rawValue).tag(status as BountyWorkflowStatus?) }
            }
            .pickerStyle(.menu)

            Picker("Risk", selection: Binding(get: { selectedRisk }, set: { selectedRisk = $0 })) {
                Text("All Risk").tag(nil as RiskLevel?)
                ForEach(RiskLevel.allCases) { risk in Text(risk.rawValue).tag(risk as RiskLevel?) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }

    private var filteredBounties: [Bounty] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bounties.filter { bounty in
            if let selectedStatus, bounty.workflowStatus != selectedStatus { return false }
            if let selectedRisk, bounty.riskLevel != selectedRisk { return false }
            guard query.isEmpty == false else { return true }
            return bounty.title.lowercased().contains(query)
                || bounty.repoSlug.lowercased().contains(query)
                || bounty.labels.joined(separator: " ").lowercased().contains(query)
                || bounty.nextAction.lowercased().contains(query)
        }
    }
}

private struct BountyDetailView: View {
    let bounty: Bounty
    @Query private var pullRequests: [PullRequest]
    @Query private var issues: [GitHubIssue]
    @Query private var ruleSets: [RepoRuleSet]
    @Query private var competitors: [CompetitorPR]
    @Query(sort: \RiskScoreSnapshot.createdAt, order: .reverse) private var riskSnapshots: [RiskScoreSnapshot]

    init(bounty: Bounty) {
        self.bounty = bounty
        let stableID = bounty.stableID
        _pullRequests = Query(filter: #Predicate<PullRequest> { $0.bountyStableID == stableID }, sort: \PullRequest.updatedAt, order: .reverse)
        _issues = Query(filter: #Predicate<GitHubIssue> { $0.bountyStableID == stableID }, sort: \GitHubIssue.updatedAt, order: .reverse)
        _ruleSets = Query(filter: #Predicate<RepoRuleSet> { $0.bountyStableID == stableID }, sort: \RepoRuleSet.updatedAt, order: .reverse)
        _competitors = Query(filter: #Predicate<CompetitorPR> { $0.bountyStableID == stableID }, sort: \CompetitorPR.updatedAt, order: .reverse)
    }

    var body: some View {
        List {
            Section("Summary") {
                HStack { Text("Payout"); Spacer(); Text(bounty.payoutText).fontWeight(.semibold) }
                LabeledContent("Risk", value: "\(bounty.riskLevel.rawValue) · \(bounty.payoutChance)%")
                LabeledContent("Next Action", value: bounty.nextAction)
                HStack(spacing: 8) {
                    StatusChip(text: bounty.workflowStatus.rawValue, systemImage: bounty.workflowStatus.systemImage, tint: .blue)
                    RiskChip(level: bounty.riskLevel)
                }
                Link("GitHub Issue", destination: bounty.githubIssueURL)
                Link("Algora Page", destination: bounty.algoraIssueURL)
                if let url = bounty.pullRequestURL { Link("Pull Request", destination: url) }
            }

            Section("Bounty Evidence") {
                EvidenceList(values: bounty.algoraEvidence, empty: "No Algora evidence detected yet.")
                EvidenceList(values: bounty.rewardLinks, empty: "No reward or claim links found.")
                LabeledContent("Claim Status", value: bounty.claimStatus.rawValue)
                LabeledContent("Already Paid/Rewarded", value: bounty.hasRewardedSignal ? "Yes" : "No")
            }

            Section("Issue") {
                Text(bounty.issueBodySummary.isEmpty ? "No issue summary cached." : bounty.issueBodySummary)
                LabeledContent("Issue Status", value: bounty.issueState.rawValue)
                if let issue = issues.first {
                    Text(issue.latestBotComment.isEmpty ? "No Algora bot comment cached." : issue.latestBotComment)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Pull Request") {
                if let pr = pullRequests.first {
                    Text(pr.bodySummary.isEmpty ? "No PR summary cached." : pr.bodySummary)
                    LabeledContent("PR Status", value: pr.state.rawValue)
                    LabeledContent("Draft", value: pr.isDraft ? "Yes" : "No")
                    LabeledContent("Mergeability", value: pr.mergeableState)
                    LabeledContent("Checks", value: pr.checkState.rawValue)
                    LabeledContent("Changed Files", value: "\(pr.changedFiles)")
                    LabeledContent("Additions / Deletions", value: "+\(pr.additions) / -\(pr.deletions)")
                    LabeledContent("Demo Proof Present", value: pr.hasDemoProof ? "Yes" : "No")
                    LabeledContent("Tests Present", value: pr.hasTests ? "Yes" : "No")
                    if pr.latestMaintainerComment.isEmpty == false {
                        Text(pr.latestMaintainerComment).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("No linked PR cached yet.").foregroundStyle(.secondary)
                }
            }

            Section("Repository Rules") {
                if let rules = ruleSets.first {
                    LabeledContent("Archived", value: rules.repoArchived ? "Yes" : "No")
                    LabeledContent("Assigned Only", value: bounty.assignedOnly ? "Yes" : "No")
                    LabeledContent("Maintainer Assignment", value: bounty.maintainerAssignmentRequired ? "Required" : "Not detected")
                    LabeledContent("User Assigned", value: bounty.userAppearsAssigned ? "Yes" : "No")
                    LabeledContent("Demo Video Required", value: rules.requiresDemoVideo ? "Yes" : "No")
                    DisclosureGroup("Code of Conduct") { Text(rules.codeOfConductSummary).font(.footnote) }
                    DisclosureGroup("CONTRIBUTING") { Text(rules.contributingSummary).font(.footnote) }
                    DisclosureGroup("README Signals") { Text(rules.readmeSummary).font(.footnote) }
                    EvidenceList(values: rules.testCommands, empty: "No test commands detected in repo docs.")
                } else {
                    Text("Repo rules are fetched during GitHub refresh.").foregroundStyle(.secondary)
                }
            }

            Section("Risk Score") {
                EvidenceList(values: bounty.riskFactors, empty: "No risk factors recorded.")
                if let last = riskSnapshots.first(where: { $0.bountyStableID == bounty.stableID }) {
                    LabeledContent("Snapshot", value: "\(last.level.rawValue) · \(last.score)%")
                }
            }

            Section("Competition") {
                LabeledContent("Competitor PRs", value: "\(competitors.count)")
                NavigationLink("Compare competitor PRs") {
                    CompetitionView(bounty: bounty)
                }
            }
        }
        .navigationTitle(bounty.issueSlug)
    }
}

private struct CompetitionView: View {
    let bounty: Bounty
    @Query private var competitors: [CompetitorPR]

    init(bounty: Bounty) {
        self.bounty = bounty
        let stableID = bounty.stableID
        _competitors = Query(filter: #Predicate<CompetitorPR> { $0.bountyStableID == stableID }, sort: \CompetitorPR.updatedAt, order: .reverse)
    }

    var body: some View {
        List {
            Section("Ethical Improvements") {
                EthicalSuggestionList(bounty: bounty)
            }
            Section("Competitor PRs") {
                if competitors.isEmpty {
                    ContentUnavailableView("No Competitors Cached", systemImage: "person.3", description: Text("Refresh to search PRs referencing this issue."))
                } else {
                    ForEach(competitors, id: \.stableID) { pr in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("#\(pr.number) · \(pr.title)").font(.headline)
                                Spacer()
                                StatusChip(text: pr.state.rawValue, systemImage: "arrow.triangle.pull", tint: pr.state == .merged ? .green : .secondary)
                            }
                            Text(pr.authorLogin).font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                StatusChip(text: pr.checkState.rawValue, systemImage: pr.checkState.systemImage, tint: pr.checkState == .failing ? .red : .green)
                                Text("\(pr.changedFiles) files · +\(pr.additions) / -\(pr.deletions)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            LabeledContent("Demo Proof", value: pr.hasDemoProof ? "Yes" : "No")
                            LabeledContent("Maintainer Approval", value: pr.hasMaintainerApproval ? "Detected" : "Not detected")
                            if pr.latestComment.isEmpty == false {
                                Text(pr.latestComment).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Competition")
    }
}

private struct DiscoverView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @State private var videoFilter: TernaryFilter = .any
    @State private var assignmentFilter: TernaryFilter = .any

    var body: some View {
        NavigationStack {
            List {
                Section("Filters") {
                    TextField("Org", text: $app.discoverFilters.org)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repo", text: $app.discoverFilters.repo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Language", text: $app.discoverFilters.language)
                        .textInputAutocapitalization(.never)
                    Stepper(value: $app.discoverFilters.minimumPayout, in: 0...25_000, step: 50) {
                        Text("Minimum payout \(dollars(app.discoverFilters.minimumPayout))")
                    }
                    Stepper(value: $app.discoverFilters.maximumPayout, in: 50...100_000, step: 50) {
                        Text("Maximum payout \(dollars(app.discoverFilters.maximumPayout))")
                    }
                    Toggle("Recently updated", isOn: $app.discoverFilters.recentlyUpdated)
                    Toggle("Low competition", isOn: $app.discoverFilters.lowCompetition)
                    Toggle("Active only", isOn: $app.discoverFilters.activeOnly)
                    Toggle("No paid/rewarded signal", isOn: $app.discoverFilters.noPaidSignal)
                    Toggle("Finishable today", isOn: $app.discoverFilters.finishableToday)
                    Toggle("Only Algora evidence", isOn: $app.discoverFilters.onlyAlgoraEvidence)
                    Picker("Video", selection: $videoFilter) {
                        ForEach(TernaryFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Assignment", selection: $assignmentFilter) {
                        ForEach(TernaryFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    Button {
                        app.discoverFilters.requiresVideo = videoFilter.value
                        app.discoverFilters.assignmentRequired = assignmentFilter.value
                        Task { await app.discover() }
                    } label: {
                        Label(app.isDiscovering ? "Searching" : "Search Bounties", systemImage: "magnifyingglass")
                    }
                    .disabled(app.isDiscovering)
                }

                Section("Results") {
                    if app.discoveredBounties.isEmpty {
                        ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Search public GitHub/Algora data for new bounties."))
                    } else {
                        ForEach(app.discoveredBounties, id: \.stableID) { bounty in
                            VStack(alignment: .leading, spacing: 8) {
                                BountySnapshotRow(snapshot: bounty)
                                Button("Track") { app.trackDiscovered(bounty) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Discover")
            .refreshable { await app.discover() }
        }
    }
}

private struct AlertsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AlertEvent.createdAt, order: .reverse) private var alerts: [AlertEvent]

    var body: some View {
        NavigationStack {
            List {
                if alerts.isEmpty {
                    ContentUnavailableView("No Alerts", systemImage: "bell", description: Text("Alerts appear after refresh detects maintainer, check, PR, issue, claim, or payment changes."))
                } else {
                    ForEach(alerts, id: \.stableID) { alert in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(alert.kind.rawValue, systemImage: alert.isRead ? "bell" : "bell.badge")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(alert.isRead ? Color.secondary : Color.accentColor)
                                Spacer()
                                Text(alert.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(alert.title).font(.headline)
                            Text(alert.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(alert.isRead ? "Unread" : "Read") {
                                alert.isRead.toggle()
                                try? modelContext.save()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Alerts")
        }
    }
}

private struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \UserAccount.updatedAt, order: .reverse) private var accounts: [UserAccount]
    @Query(sort: \WatchedOrg.handle) private var watchedOrgs: [WatchedOrg]
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var bounties: [Bounty]
    @State private var githubToken = ""
    @State private var algoraToken = ""
    @State private var newOrg = ""
    @AppStorage("refreshIntervalMinutes") private var refreshIntervalMinutes = 30
    @AppStorage("notifyMaintainerComments") private var notifyMaintainerComments = true
    @AppStorage("notifyChecks") private var notifyChecks = true
    @AppStorage("notifyPayment") private var notifyPayment = true
    @AppStorage("defaultMinimumPayout") private var defaultMinimumPayout = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub Auth Status") {
                    if let account = accounts.first {
                        LabeledContent("User", value: account.githubLogin)
                        LabeledContent("GitHub Token", value: account.hasGitHubToken ? "Stored in Keychain" : "Missing")
                        LabeledContent("Algora Token", value: account.hasAlgoraToken ? "Stored in Keychain" : "Not configured")
                        if let date = account.lastValidatedAt { LabeledContent("Validated", value: date.formatted()) }
                    } else {
                        Text("No GitHub account validated yet.")
                    }
                }

                Section("GitHub Token Management") {
                    SecureField("New GitHub token", text: $githubToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Validate and Save GitHub Token") { Task { await app.saveGitHubToken(githubToken) } }
                        .disabled(githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove GitHub Token", role: .destructive) { app.clearGitHubToken() }
                }

                Section("Optional Algora Token") {
                    SecureField("Algora API token", text: $algoraToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Optional Algora Token") { app.saveAlgoraToken(algoraToken) }
                    Button("Remove Algora Token") { app.saveAlgoraToken("") }
                }

                Section("API Access Help") {
                    Text(apiAccessHelpText).font(.footnote)
                    Button { app.copyToClipboard(algoraSupportMessage) } label: { Label("Copy Support Message", systemImage: "doc.on.doc") }
                }

                Section("Watched Orgs") {
                    HStack {
                        TextField("org", text: $newOrg)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button { addOrg() } label: { Image(systemName: "plus.circle.fill") }
                            .disabled(newOrg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ForEach(watchedOrgs, id: \.handle) { org in
                        Toggle(org.displayName, isOn: Binding(get: { org.isEnabled }, set: { org.isEnabled = $0; try? modelContext.save() }))
                    }
                    .onDelete { offsets in
                        for index in offsets { modelContext.delete(watchedOrgs[index]) }
                        try? modelContext.save()
                    }
                }

                Section("Default Payout Filters") {
                    Stepper(value: $defaultMinimumPayout, in: 0...25_000, step: 50) {
                        Text("Minimum \(dollars(defaultMinimumPayout))")
                    }
                }

                Section("Refresh") {
                    Stepper("Every \(refreshIntervalMinutes) minutes", value: $refreshIntervalMinutes, in: 15...240, step: 15)
                    Button("Refresh Now") { Task { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) } }
                }

                Section("Notifications") {
                    Toggle("Maintainer comments", isOn: $notifyMaintainerComments)
                    Toggle("Check changes", isOn: $notifyChecks)
                    Toggle("Payment and claim changes", isOn: $notifyPayment)
                }

                Section("Export") {
                    ShareLink("Export tracker as Markdown", item: app.markdownExport(for: bounties))
                    ShareLink("Export tracker as CSV", item: app.csvExport(for: bounties))
                }

                Section("Cache") {
                    Button("Clear cached tracker data", role: .destructive) { app.clearCachedData() }
                    Text("This clears fetched bounties, PRs, rules, competitors, alerts, and risk snapshots. Tokens stay in Keychain unless removed above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func addOrg() {
        let handle = newOrg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard handle.isEmpty == false else { return }
        modelContext.insert(WatchedOrg(handle: handle))
        try? modelContext.save()
        newOrg = ""
    }
}

private struct AddBountyView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub or Algora URL") {
                    TextField("https://github.com/org/repo/issues/123", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if errorMessage.isEmpty == false {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section("Import") {
                    Text("Manual imports are not seeded data. They create a draft record from the URL, then GitHub refresh fills live issue, PR, checks, rules, and competition data when possible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Bounty")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if app.addManualURL(urlText) {
                            dismiss()
                        } else {
                            errorMessage = "Enter a GitHub issue/PR URL or an Algora issue URL."
                        }
                    }
                }
            }
        }
    }
}

private struct BountyRow: View {
    let bounty: Bounty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bounty.title).font(.headline).lineLimit(2)
                Spacer()
                Text(bounty.payoutText).font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
            Text(bounty.issueSlug).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                StatusChip(text: bounty.workflowStatus.rawValue, systemImage: bounty.workflowStatus.systemImage, tint: .blue)
                StatusChip(text: bounty.checkState.rawValue, systemImage: bounty.checkState.systemImage, tint: bounty.checkState == .failing ? .red : .green)
                RiskChip(level: bounty.riskLevel)
            }
            Text(bounty.nextAction).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 6)
    }
}

private struct BountyCompactRow: View {
    let bounty: Bounty

    var body: some View {
        NavigationLink {
            BountyDetailView(bounty: bounty)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(bounty.payoutText).foregroundStyle(.green)
                }
                Text(bounty.title).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

private struct BountySnapshotRow: View {
    let snapshot: TrackedBountySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.title).font(.headline).lineLimit(2)
                Spacer()
                Text(snapshot.amount > 0 ? snapshot.amount.formatted(.currency(code: snapshot.currency).precision(.fractionLength(0))) : "TBD")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Text("\(snapshot.repoOwner)/\(snapshot.repoName)#\(snapshot.issueNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                RiskChip(level: snapshot.riskLevel)
                StatusChip(text: "\(snapshot.competitionCount) signals", systemImage: "person.3", tint: .secondary)
            }
            Text(snapshot.nextAction).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

private struct ActionRow: View {
    let bounty: Bounty

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                Spacer()
                RiskChip(level: bounty.riskLevel)
            }
            Text(bounty.nextAction).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct SyncBanner: View {
    let message: String
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: warnings.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.subheadline)
            ForEach(warnings.prefix(3), id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .floatingGlassControl()
    }
}

private struct StatusChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(text)
    }
}

private struct RiskChip: View {
    let level: RiskLevel

    var body: some View {
        StatusChip(text: "\(level.rawValue) Risk", systemImage: "gauge.with.dots.needle.67percent", tint: tint)
    }

    private var tint: Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

private struct EvidenceList: View {
    let values: [String]
    let empty: String

    var body: some View {
        if values.isEmpty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: "checkmark.circle")
                    .font(.footnote)
            }
        }
    }
}

private struct EthicalSuggestionList: View {
    let bounty: Bounty

    var body: some View {
        EvidenceList(values: suggestions, empty: "No immediate improvement suggestions detected.")
    }

    private var suggestions: [String] {
        var values: [String] = []
        if bounty.hasTests == false { values.append("Add missing tests or explain why tests do not apply.") }
        if bounty.hasClearVerification == false { values.append("Improve the PR body with clearer verification steps.") }
        if bounty.checkState == .failing { values.append("Address failing checks before asking for review.") }
        if bounty.requiresVideo && bounty.hasDemoProof == false { values.append("Add real demo proof if the bounty requires it.") }
        if bounty.assignedOnly && bounty.userAppearsAssigned == false { values.append("Confirm assignment before expanding scope.") }
        if bounty.latestMaintainerComment.isEmpty == false { values.append("Respond to relevant maintainer feedback.") }
        if bounty.riskFactors.contains(where: { $0.lowercased().contains("contributing") }) { values.append("Mention the relevant repository rules in the PR.") }
        return values
    }
}

private enum TernaryFilter: String, CaseIterable, Identifiable {
    case any = "Any"
    case yes = "Required"
    case no = "Not Required"

    var id: String { rawValue }
    var value: Bool? {
        switch self {
        case .any: return nil
        case .yes: return true
        case .no: return false
        }
    }
}

private func riskRank(_ risk: RiskLevel) -> Int {
    switch risk {
    case .high: return 3
    case .medium: return 2
    case .low: return 1
    }
}

private func dollars(_ amount: Int) -> String {
    amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}
