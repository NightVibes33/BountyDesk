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
            await app.resumeGitHubDeviceLoginIfNeeded()
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
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar.badge.clock") }
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
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var githubToken = ""
    @State private var algoraToken = ""
    @State private var includePrivateRepositories = false

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LoginHero()

                        VStack(alignment: .leading, spacing: 16) {
                            Button {
                                Task {
                                    if let url = await app.startGitHubDeviceLogin(includePrivateRepositories: includePrivateRepositories) {
                                        openURL(url)
                                    }
                                }
                            } label: {
                                Label(app.isStartingGitHubDeviceLogin ? "Preparing GitHub" : "Continue with GitHub Passkey", systemImage: "key.horizontal")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(app.isStartingGitHubDeviceLogin || app.isFinishingGitHubDeviceLogin || app.githubDeviceAuthorization != nil)
                            .symbolEffect(.bounce, value: app.githubDeviceAuthorization != nil)

                            Toggle("Include private repositories", isOn: $includePrivateRepositories)
                            Text(includePrivateRepositories ? "Request private and public repository read access." : "Request public repository read access.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if let authorization = app.githubDeviceAuthorization {
                                GitHubDeviceLoginPanel(authorization: authorization)
                                    .padding(.vertical, 6)
                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            }

                            Divider().overlay(.secondary.opacity(0.25))

                            SecureField("GitHub personal access token", text: $githubToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button {
                                Task { await app.saveGitHubToken(githubToken) }
                            } label: {
                                Label("Use GitHub Token", systemImage: "checkmark.shield")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(18)
                        .bountyGlassCard(cornerRadius: 8, interactive: true)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Optional Algora API", systemImage: "link.badge.plus")
                                .font(.headline)
                            SecureField("Algora API token", text: $algoraToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("Save Optional Algora Token") { app.saveAlgoraToken(algoraToken) }
                                .buttonStyle(.bordered)
                            Text("Most solver accounts can continue without this. GitHub login is enough for PR, issue, comment, check, and public bounty evidence.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .bountyGlassCard(cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(apiAccessHelpText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button { app.copyToClipboard(algoraSupportMessage) } label: {
                                Label("Copy Algora Support Message", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(18)
                        .bountyGlassCard(cornerRadius: 8)

                        if let error = app.authError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .bountyGlassCard(cornerRadius: 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            if app.githubDeviceAuthorization != nil {
                                Button {
                                    Task { await app.finishGitHubDeviceLogin() }
                                } label: {
                                    Label("Check Sign In Again", systemImage: "arrow.clockwise.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(app.isFinishingGitHubDeviceLogin)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("BountyDesk")
            .navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .snappy, value: app.githubDeviceAuthorization != nil)
            .animation(reduceMotion ? nil : .snappy, value: app.authError)
        }
    }
}

private struct LoginHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.18))
                    .frame(width: 76, height: 76)
                Image(systemName: "target")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("BountyDesk")
                    .font(.largeTitle.weight(.bold))
                Text("Track Algora bounty PRs, claim status, checks, maintainer signals, and payout risk from GitHub.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

private struct GitHubDeviceLoginPanel: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Environment(\.openURL) private var openURL
    let authorization: GitHubDeviceAuthorization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Code") {
                Text(authorization.userCode)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
            }
            LabeledContent("Access", value: authorization.scopeDescription)
            if app.isFinishingGitHubDeviceLogin {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for GitHub approval.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("Approve in GitHub, then return here. BountyDesk keeps this code until it expires.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Expires") {
                Text(authorization.expiresAt, style: .relative)
            }
            HStack {
                Button {
                    if let url = authorization.verificationURL { openURL(url) }
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                }
                Button {
                    app.copyToClipboard(authorization.userCode)
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                }
            }
            Button {
                Task { await app.finishGitHubDeviceLogin() }
            } label: {
                Label(app.isFinishingGitHubDeviceLogin ? "Waiting for GitHub" : "Check Sign In Now", systemImage: "checkmark.circle")
            }
            .disabled(app.isFinishingGitHubDeviceLogin)
            Button("Cancel", role: .cancel) { app.cancelGitHubDeviceLogin() }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

private struct TodayView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \WatchedOrg.handle) private var watchedOrgs: [WatchedOrg]
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var bounties: [Bounty]
    @Query(sort: \AlertEvent.createdAt, order: .reverse) private var alerts: [AlertEvent]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        TodayHero(
                            value: activeValue,
                            dueCount: dueFollowUps.count,
                            focusCount: focusQueue.count,
                            payoutCount: payoutQueue.count,
                            isRefreshing: app.isRefreshing,
                            lastRefresh: app.refreshDiagnostics.updatedAt
                        )

                        if let syncMessage = app.syncMessage {
                            SyncBanner(message: syncMessage, warnings: app.warnings)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        BountySectionHeader(title: "Work Queue", systemImage: "bolt.badge.clock")
                        if workQueue.isEmpty {
                            EmptyStatePanel(title: "Nothing Needs Attention", systemImage: "checkmark.seal", message: "Pinned, due, failing, waiting, and payout bounties collect here.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(workQueue, id: \.stableID) { bounty in
                                    NavigationLink {
                                        BountyDetailView(bounty: bounty)
                                    } label: {
                                        ActionRow(bounty: bounty)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            MetricTile(title: "Due", value: "\(dueFollowUps.count)", systemImage: "calendar.badge.exclamationmark", tint: .red)
                            MetricTile(title: "Focus", value: "\(focusQueue.count)", systemImage: "scope", tint: .orange)
                            MetricTile(title: "Waiting", value: "\(waitingQueue.count)", systemImage: "clock", tint: .blue)
                            MetricTile(title: "Payout", value: "\(payoutQueue.count)", systemImage: "banknote", tint: .purple)
                        }

                        TodayBountyGroup(title: "Due Follow-ups", systemImage: "calendar", bounties: dueFollowUps)
                        TodayBountyGroup(title: "Waiting On Review", systemImage: "text.badge.checkmark", bounties: waitingQueue)
                        TodayBountyGroup(title: "Payout Watch", systemImage: "banknote", bounties: payoutQueue)

                        BountySectionHeader(title: "Unread Alerts", systemImage: "bell.badge")
                        if unreadAlerts.isEmpty {
                            EmptyStatePanel(title: "No Unread Alerts", systemImage: "bell", message: "Refresh changes and bounty events show here.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(unreadAlerts.prefix(4), id: \.stableID) { alert in
                                    AlertCard(alert: alert)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
                    } label: {
                        Image(systemName: app.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                            .symbolEffect(.bounce, value: app.isRefreshing)
                    }
                    .disabled(app.isRefreshing)
                    .accessibilityLabel("Refresh bounties")
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: app.syncMessage)
            .animation(reduceMotion ? nil : .snappy, value: bounties.count)
        }
    }

    private var visibleBounties: [Bounty] {
        bounties.filter { $0.managementStage != .archived && $0.workflowStatus != .lost && $0.workflowStatus != .blocked }
    }

    private var activeValue: String {
        visibleBounties
            .filter { $0.workflowStatus != .paid }
            .reduce(0) { $0 + $1.amount }
            .formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private var dueFollowUps: [Bounty] { visibleBounties.filter(\.isFollowUpDue).sorted(by: todaySort) }

    private var focusQueue: [Bounty] {
        visibleBounties.filter { bounty in
            bounty.managementStage == .focus
                || bounty.userPriority == .urgent
                || bounty.checkState == .failing
                || bounty.riskLevel == .high
        }
        .sorted(by: todaySort)
    }

    private var waitingQueue: [Bounty] {
        visibleBounties.filter { $0.managementStage == .waiting || $0.workflowStatus == .pendingReview }
            .sorted(by: todaySort)
    }

    private var payoutQueue: [Bounty] {
        visibleBounties.filter { bounty in
            bounty.managementStage == .payout
                || bounty.workflowStatus == .mergedUnpaid
                || bounty.claimStatus == .accepted
                || bounty.claimStatus == .paymentProcessing
        }
        .sorted(by: todaySort)
    }

    private var workQueue: [Bounty] {
        var seen = Set<String>()
        return (dueFollowUps + focusQueue + payoutQueue + waitingQueue + visibleBounties.filter(\.isPinned))
            .filter { seen.insert($0.stableID).inserted }
            .sorted(by: todaySort)
            .prefix(8)
            .map { $0 }
    }

    private var unreadAlerts: [AlertEvent] { alerts.filter { $0.isRead == false } }

    private func todaySort(_ lhs: Bounty, _ rhs: Bounty) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.isFollowUpDue != rhs.isFollowUpDue { return lhs.isFollowUpDue }
        let priorityDelta = priorityRank(lhs.userPriority) - priorityRank(rhs.userPriority)
        if priorityDelta != 0 { return priorityDelta > 0 }
        if lhs.amount != rhs.amount { return lhs.amount > rhs.amount }
        return lhs.updatedAt > rhs.updatedAt
    }
}

private struct TodayHero: View {
    let value: String
    let dueCount: Int
    let focusCount: Int
    let payoutCount: Int
    let isRefreshing: Bool
    let lastRefresh: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Command center", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastRefresh {
                    Text(lastRefresh, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(value)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.65)
            Text("\(dueCount) due · \(focusCount) focus · \(payoutCount) payout watch")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                StatusChip(text: isRefreshing ? "Refreshing" : "Ready", systemImage: isRefreshing ? "arrow.clockwise" : "checkmark.circle", tint: isRefreshing ? .blue : .green)
                if dueCount > 0 {
                    StatusChip(text: "Follow up", systemImage: "calendar.badge.exclamationmark", tint: .red)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

private struct TodayBountyGroup: View {
    let title: String
    let systemImage: String
    let bounties: [Bounty]

    var body: some View {
        if bounties.isEmpty == false {
            BountySectionHeader(title: title, systemImage: systemImage)
            VStack(spacing: 10) {
                ForEach(bounties.prefix(4), id: \.stableID) { bounty in
                    BountyCompactRow(bounty: bounty)
                }
            }
        }
    }
}

private struct AlertCard: View {
    let alert: AlertEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(alert.kind.rawValue, systemImage: alert.isRead ? "bell" : "bell.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alert.isRead ? Color.secondary : Color.accentColor)
                Spacer()
                Text(alert.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(alert.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(alert.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
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
            ZStack {
                BountyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        DashboardHero(
                            totalValue: totalActiveValue,
                            activeCount: activeBounties.count,
                            pendingReviewCount: pendingReviewCount,
                            mergedUnpaidCount: mergedUnpaidCount,
                            alertCount: alerts.count,
                            isRefreshing: app.isRefreshing,
                            trigger: app.refreshDiagnostics.updatedAt
                        )

                        if let syncMessage = app.syncMessage {
                            SyncBanner(message: syncMessage, warnings: app.warnings)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            MetricTile(title: "Active Potential", value: totalActiveValue, systemImage: "dollarsign.circle", tint: .green)
                            MetricTile(title: "Algora PRs", value: "\(activeClaimedPRCount)", systemImage: "flag", tint: .blue)
                            MetricTile(title: "Pending Review", value: "\(pendingReviewCount)", systemImage: "text.badge.checkmark", tint: .orange)
                            MetricTile(title: "Merged Unpaid", value: "\(mergedUnpaidCount)", systemImage: "arrow.triangle.merge", tint: .purple)
                            MetricTile(title: "Closed/Lost", value: "\(lostCount)", systemImage: "xmark.circle", tint: .secondary)
                            MetricTile(title: "Checks Failing", value: "\(failingChecksCount)", systemImage: "xmark.octagon", tint: .red)
                        }

                        BountySectionHeader(title: "Highest Priority Next Actions", systemImage: "bolt.badge.clock")
                        if priorityActions.isEmpty {
                            EmptyStatePanel(title: "No Actions", systemImage: "checkmark.seal", message: "Refresh after signing in to build your current Algora bounty tracker.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(priorityActions, id: \.stableID) { bounty in
                                    NavigationLink {
                                        BountyDetailView(bounty: bounty)
                                    } label: {
                                        ActionRow(bounty: bounty)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        BountySectionHeader(title: "Likely To Pay Soon", systemImage: "banknote")
                        if likelyToPaySoon.isEmpty {
                            EmptyStatePanel(title: "No payout signals", systemImage: "hourglass", message: "Accepted, processing, and merged-unpaid bounties will collect here.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(likelyToPaySoon, id: \.stableID) { bounty in
                                    BountyCompactRow(bounty: bounty)
                                }
                            }
                        }

                        BountySectionHeader(title: "At Risk", systemImage: "exclamationmark.triangle")
                        if atRisk.isEmpty {
                            EmptyStatePanel(title: "No high-risk bounties", systemImage: "shield.checkered", message: "Failing checks, archived repos, and risky payout signals will show here.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(atRisk, id: \.stableID) { bounty in
                                    BountyCompactRow(bounty: bounty)
                                }
                            }
                        }

                        BountySectionHeader(title: "Latest Maintainer Comments", systemImage: "text.bubble")
                        if latestMaintainerComments.isEmpty {
                            EmptyStatePanel(title: "No maintainer comments", systemImage: "bubble.left", message: "New maintainer signals appear after refresh.")
                        } else {
                            VStack(spacing: 10) {
                                ForEach(latestMaintainerComments, id: \.stableID) { bounty in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                                        Text(bounty.latestMaintainerComment).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .bountyGlassCard(cornerRadius: 8)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
            }
            .navigationTitle("BountyDesk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
                    } label: {
                        Image(systemName: app.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                            .symbolEffect(.bounce, value: app.isRefreshing)
                    }
                    .disabled(app.isRefreshing)
                    .accessibilityLabel("Refresh bounties")
                }
            }
            .sensoryFeedback(.success, trigger: app.refreshDiagnostics.updatedAt)
            .animation(reduceMotion ? nil : .snappy, value: app.syncMessage)
            .animation(reduceMotion ? nil : .snappy, value: bounties.count)
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

private struct DashboardHero: View {
    let totalValue: String
    let activeCount: Int
    let pendingReviewCount: Int
    let mergedUnpaidCount: Int
    let alertCount: Int
    let isRefreshing: Bool
    let trigger: Date?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { heroText; Spacer(minLength: 18); BountyOrbitGraphic(trigger: trigger, isRefreshing: isRefreshing) }
            VStack(alignment: .leading, spacing: 20) { heroText; BountyOrbitGraphic(trigger: trigger, isRefreshing: isRefreshing) }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Algora bounty command", systemImage: "scope")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(totalValue)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.65)
            Text("\(activeCount) active · \(pendingReviewCount) in review · \(mergedUnpaidCount) merged unpaid")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            if alertCount > 0 {
                StatusChip(text: "\(alertCount) alerts", systemImage: "bell.badge", tint: .orange)
            }
        }
    }
}

private struct BountyOrbitGraphic: View {
    let trigger: Date?
    let isRefreshing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(.green.opacity(0.25), lineWidth: 18)
                .frame(width: 118, height: 118)
            Circle()
                .stroke(.blue.opacity(0.24), lineWidth: 12)
                .frame(width: 84, height: 84)
            Circle()
                .fill(.green.opacity(0.22))
                .frame(width: 46, height: 46)
            Image(systemName: isRefreshing ? "arrow.clockwise" : "bolt.horizontal.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: isRefreshing)
        }
        .frame(width: 132, height: 132)
        .phaseAnimator(reduceMotion ? [0] : [0, 1, 2], trigger: trigger) { content, phase in
            content
                .scaleEffect(phase == 1 ? 1.04 : 1.0)
                .rotationEffect(.degrees(phase == 2 ? 6 : 0))
        } animation: { phase in
            phase == 1 ? .snappy(duration: 0.28) : .smooth(duration: 0.36)
        }
        .accessibilityHidden(true)
    }
}

private struct EmptyStatePanel: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity)
            .padding(12)
            .bountyGlassCard(cornerRadius: 8)
    }
}

private struct BountyListView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \WatchedOrg.handle) private var watchedOrgs: [WatchedOrg]
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var bounties: [Bounty]
    @State private var searchText = ""
    @State private var selectedStage: BountyManagementStage?
    @State private var selectedStatus: BountyWorkflowStatus?
    @State private var selectedRisk: RiskLevel?
    @State private var selectedPriority: BountyUserPriority?
    @State private var showArchived = false
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
                List {
                    Section {
                        BountyManagementPanel(bounties: bounties, diagnostics: app.refreshDiagnostics)
                        ManagementStageBoard(bounties: bounties, selectedStage: $selectedStage)
                        filters
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)

                    if filteredBounties.isEmpty {
                        ContentUnavailableView("No Managed Bounties", systemImage: "tray", description: Text("Refresh or track a verified Algora bounty, then assign a stage, priority, follow-up, tags, and notes."))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredBounties, id: \.stableID) { bounty in
                            NavigationLink {
                                BountyDetailView(bounty: bounty)
                            } label: {
                                BountyRow(bounty: bounty)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button { app.togglePinned(bounty) } label: {
                                    Label(bounty.isPinned ? "Unpin" : "Pin", systemImage: bounty.isPinned ? "star.slash" : "star")
                                }
                                .tint(.yellow)
                                Button { app.setManagementStage(.focus, for: bounty) } label: {
                                    Label("Focus", systemImage: BountyManagementStage.focus.systemImage)
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { app.setManagementStage(.archived, for: bounty) } label: {
                                    Label("Archive", systemImage: BountyManagementStage.archived.systemImage)
                                }
                                Button { app.setManagementStage(.waiting, for: bounty) } label: {
                                    Label("Waiting", systemImage: BountyManagementStage.waiting.systemImage)
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button { app.togglePinned(bounty) } label: {
                                    Label(bounty.isPinned ? "Unpin" : "Pin", systemImage: bounty.isPinned ? "star.slash" : "star")
                                }
                                Menu("Move to Stage") {
                                    ForEach(BountyManagementStage.allCases) { stage in
                                        Button { app.setManagementStage(stage, for: bounty) } label: {
                                            Label(stage.rawValue, systemImage: stage.systemImage)
                                        }
                                    }
                                }
                                Menu("Priority") {
                                    ForEach(BountyUserPriority.allCases) { priority in
                                        Button { app.setPriority(priority, for: bounty) } label: {
                                            Label(priority.rawValue, systemImage: priority.systemImage)
                                        }
                                    }
                                }
                                Divider()
                                Link("Open GitHub Issue", destination: bounty.githubIssueURL)
                                Link("Open Algora Page", destination: bounty.algoraIssueURL)
                                if let url = bounty.pullRequestURL { Link("Open Pull Request", destination: url) }
                                Divider()
                                Button(role: .destructive) { app.deleteBounty(bounty) } label: {
                                    Label("Remove From Tracking", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) }
            }
            .searchable(text: $searchText, prompt: "Repo, title, tag, note, next action")
            .navigationTitle("Bounty Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import bounty URL")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await app.refreshCurrentBounties(watchedOrgs: watchedOrgs) } } label: {
                        Image(systemName: "arrow.clockwise")
                            .symbolEffect(.bounce, value: app.isRefreshing)
                    }
                    .disabled(app.isRefreshing)
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $isAdding) { AddBountyView() }
            .animation(reduceMotion ? nil : .snappy, value: selectedStage)
            .animation(reduceMotion ? nil : .snappy, value: showArchived)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Manage", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text("\(filteredBounties.count)")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(.secondary)
            }
            Picker("Stage", selection: Binding(get: { selectedStage }, set: { selectedStage = $0 })) {
                Text("All Stages").tag(nil as BountyManagementStage?)
                ForEach(BountyManagementStage.allCases) { stage in Text(stage.rawValue).tag(stage as BountyManagementStage?) }
            }
            .pickerStyle(.menu)

            Picker("Priority", selection: Binding(get: { selectedPriority }, set: { selectedPriority = $0 })) {
                Text("All Priority").tag(nil as BountyUserPriority?)
                ForEach(BountyUserPriority.allCases) { priority in Text(priority.rawValue).tag(priority as BountyUserPriority?) }
            }
            .pickerStyle(.segmented)

            HStack {
                Picker("Status", selection: Binding(get: { selectedStatus }, set: { selectedStatus = $0 })) {
                    Text("All Status").tag(nil as BountyWorkflowStatus?)
                    ForEach(BountyWorkflowStatus.allCases) { status in Text(status.rawValue).tag(status as BountyWorkflowStatus?) }
                }
                .pickerStyle(.menu)

                Picker("Risk", selection: Binding(get: { selectedRisk }, set: { selectedRisk = $0 })) {
                    Text("All Risk").tag(nil as RiskLevel?)
                    ForEach(RiskLevel.allCases) { risk in Text(risk.rawValue).tag(risk as RiskLevel?) }
                }
                .pickerStyle(.menu)
            }

            Toggle("Show archived", isOn: $showArchived)
                .font(.subheadline)
        }
        .padding(14)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }

    private var filteredBounties: [Bounty] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bounties.filter { bounty in
            if showArchived == false && bounty.managementStage == .archived { return false }
            if let selectedStage, bounty.managementStage != selectedStage { return false }
            if let selectedStatus, bounty.workflowStatus != selectedStatus { return false }
            if let selectedRisk, bounty.riskLevel != selectedRisk { return false }
            if let selectedPriority, bounty.userPriority != selectedPriority { return false }
            guard query.isEmpty == false else { return true }
            return bounty.title.lowercased().contains(query)
                || bounty.repoSlug.lowercased().contains(query)
                || bounty.labels.joined(separator: " ").lowercased().contains(query)
                || bounty.userTags.joined(separator: " ").lowercased().contains(query)
                || bounty.userNotes.lowercased().contains(query)
                || bounty.nextAction.lowercased().contains(query)
        }
        .sorted(by: managementSort)
    }

    private func managementSort(_ lhs: Bounty, _ rhs: Bounty) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.isFollowUpDue != rhs.isFollowUpDue { return lhs.isFollowUpDue }
        let priorityDelta = priorityRank(lhs.userPriority) - priorityRank(rhs.userPriority)
        if priorityDelta != 0 { return priorityDelta > 0 }
        let stageDelta = stageRank(lhs.managementStage) - stageRank(rhs.managementStage)
        if stageDelta != 0 { return stageDelta > 0 }
        return lhs.updatedAt > rhs.updatedAt
    }
}

private struct BountyManagementPanel: View {
    let bounties: [Bounty]
    let diagnostics: RefreshDiagnostics

    private var activeBounties: [Bounty] {
        bounties.filter { ![BountyWorkflowStatus.paid, .lost, .blocked].contains($0.workflowStatus) && $0.managementStage != .archived }
    }

    private var needsActionCount: Int {
        activeBounties.filter { bounty in
            bounty.managementStage == .focus
                || bounty.userPriority == .urgent
                || bounty.isFollowUpDue
                || bounty.riskLevel == .high
                || bounty.checkState == .failing
        }.count
    }

    private var pinnedCount: Int { bounties.filter(\.isPinned).count }
    private var dueFollowUpCount: Int { bounties.filter(\.isFollowUpDue).count }
    private var archivedCount: Int { bounties.filter { $0.managementStage == .archived }.count }
    private var payoutCount: Int { bounties.filter { $0.managementStage == .payout || $0.workflowStatus == .mergedUnpaid || $0.claimStatus == .paymentProcessing }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Bounty management", systemImage: "square.grid.2x2")
                    .font(.headline.weight(.semibold))
                Spacer()
                if let updatedAt = diagnostics.updatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ManagementMetric(title: "Active", value: "\(activeBounties.count)", systemImage: "flag", tint: .blue)
                ManagementMetric(title: "Needs Action", value: "\(needsActionCount)", systemImage: "bolt.badge.clock", tint: .orange)
                ManagementMetric(title: "Pinned", value: "\(pinnedCount)", systemImage: "star", tint: .yellow)
                ManagementMetric(title: "Payout Queue", value: "\(payoutCount)", systemImage: "banknote", tint: .purple)
            }
            StagePipeline(bounties: bounties)
            if dueFollowUpCount > 0 || archivedCount > 0 {
                HStack(spacing: 8) {
                    if dueFollowUpCount > 0 {
                        StatusChip(text: "\(dueFollowUpCount) due", systemImage: "calendar.badge.exclamationmark", tint: .red)
                    }
                    if archivedCount > 0 {
                        StatusChip(text: "\(archivedCount) archived", systemImage: "archivebox", tint: .secondary)
                    }
                }
            }
            Text("Saved bounties now keep local stage, priority, follow-up, tags, notes, and pinned state across refreshes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

private struct ManagementStageBoard: View {
    let bounties: [Bounty]
    @Binding var selectedStage: BountyManagementStage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Stage board", systemImage: "rectangle.3.group")
                    .font(.headline.weight(.semibold))
                Spacer()
                if selectedStage != nil {
                    Button("Clear") {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            selectedStage = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(BountyManagementStage.allCases) { stage in
                        let stageBounties = bounties.filter { $0.managementStage == stage }
                        StageBoardCard(
                            stage: stage,
                            count: stageBounties.count,
                            value: stageValue(stageBounties),
                            dueCount: stageBounties.filter(\.isFollowUpDue).count,
                            workPRCount: stageBounties.reduce(0) { $0 + $1.competitionCount },
                            isSelected: selectedStage == stage
                        ) {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                selectedStage = selectedStage == stage ? nil : stage
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }

    private func stageValue(_ values: [Bounty]) -> String {
        values.reduce(0) { $0 + $1.amount }.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

private struct StageBoardCard: View {
    let stage: BountyManagementStage
    let count: Int
    let value: String
    let dueCount: Int
    let workPRCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Image(systemName: stage.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(stage.tint)
                        .frame(width: 30, height: 30)
                        .background(stage.tint.opacity(0.14), in: Circle())
                    Spacer()
                    Text("\(count)")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText())
                }
                Text(stage.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { signalChips }
                    VStack(alignment: .leading, spacing: 5) { signalChips }
                }
                .frame(height: 42, alignment: .topLeading)
            }
            .padding(12)
            .frame(width: 166, height: 166, alignment: .topLeading)
            .background(stage.tint.opacity(isSelected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? stage.tint.opacity(0.65) : Color.secondary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.rawValue), \(count) bounties, \(value)")
    }

    @ViewBuilder
    private var signalChips: some View {
        if dueCount > 0 {
            StatusChip(text: "\(dueCount) due", systemImage: "calendar.badge.exclamationmark", tint: .red)
        }
        if workPRCount > 0 {
            StatusChip(text: workPullRequestText(workPRCount), systemImage: "person.3", tint: .orange)
        }
    }
}

private struct StagePipeline: View {
    let bounties: [Bounty]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BountyManagementStage.allCases) { stage in
                    StageCountPill(stage: stage, count: bounties.filter { $0.managementStage == stage }.count)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct StageCountPill: View {
    let stage: BountyManagementStage
    let count: Int

    var body: some View {
        Label("\(stage.rawValue) \(count)", systemImage: stage.systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(stage.tint)
            .background(stage.tint.opacity(0.13), in: Capsule())
    }
}

private struct ManagementMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct BountyDetailView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    let bounty: Bounty
    @Query private var pullRequests: [PullRequest]
    @Query private var issues: [GitHubIssue]
    @Query private var ruleSets: [RepoRuleSet]
    @Query private var competitors: [CompetitorPR]
    @Query private var checklistItems: [BountyChecklistItem]
    @Query(sort: \RiskScoreSnapshot.createdAt, order: .reverse) private var riskSnapshots: [RiskScoreSnapshot]

    init(bounty: Bounty) {
        self.bounty = bounty
        let stableID = bounty.stableID
        _pullRequests = Query(filter: #Predicate<PullRequest> { $0.bountyStableID == stableID }, sort: \PullRequest.updatedAt, order: .reverse)
        _issues = Query(filter: #Predicate<GitHubIssue> { $0.bountyStableID == stableID }, sort: \GitHubIssue.updatedAt, order: .reverse)
        _ruleSets = Query(filter: #Predicate<RepoRuleSet> { $0.bountyStableID == stableID }, sort: \RepoRuleSet.updatedAt, order: .reverse)
        _competitors = Query(filter: #Predicate<CompetitorPR> { $0.bountyStableID == stableID }, sort: \CompetitorPR.updatedAt, order: .reverse)
        _checklistItems = Query(filter: #Predicate<BountyChecklistItem> { $0.bountyStableID == stableID }, sort: \BountyChecklistItem.sortIndex)
    }

    var body: some View {
        ZStack {
            BountyBackdrop()
            List {
            Section {
                BountyDetailHero(
                    bounty: bounty,
                    competitorCount: competitors.count,
                    openChecklistCount: checklistItems.filter { $0.isDone == false }.count,
                    completedChecklistCount: checklistItems.filter(\.isDone).count
                )
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)

            BountyManagementEditor(bounty: bounty)
            BountyChecklistSection(bounty: bounty, items: checklistItems)

            Section("Summary") {
                LabeledContent("Source", value: "Verified Algora bounty")
                HStack { Text("Payout"); Spacer(); Text(bounty.payoutText).fontWeight(.semibold) }
                LabeledContent("Attempt / Claim Flow", value: bounty.algoraEvidence.contains("Algora claim flow found") ? "Detected" : "Missing")
                LabeledContent("Reward Status", value: bounty.hasRewardedSignal ? "Rewarded or paid" : bounty.claimStatus.rawValue)
                LabeledContent("Last Checked", value: bounty.lastRefreshedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not checked")
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
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(bounty.issueSlug)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { app.togglePinned(bounty) } label: {
                    Image(systemName: bounty.isPinned ? "star.fill" : "star")
                }
                .accessibilityLabel(bounty.isPinned ? "Unpin bounty" : "Pin bounty")
                Menu {
                    ForEach(BountyManagementStage.allCases) { stage in
                        Button { app.setManagementStage(stage, for: bounty) } label: {
                            Label(stage.rawValue, systemImage: stage.systemImage)
                        }
                    }
                    Divider()
                    Button(role: .destructive) { app.deleteBounty(bounty) } label: {
                        Label("Remove From Tracking", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
}

private struct BountyDetailHero: View {
    let bounty: Bounty
    let competitorCount: Int
    let openChecklistCount: Int
    let completedChecklistCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                heroText
                Spacer(minLength: 12)
                BountySignalDial(bounty: bounty, competitorCount: competitorCount)
            }
            VStack(alignment: .leading, spacing: 18) {
                heroText
                BountySignalDial(bounty: bounty, competitorCount: competitorCount)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bounty.payoutText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 8)
                if bounty.isPinned {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Pinned")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(bounty.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(bounty.issueSlug)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { statusBadges }
                VStack(alignment: .leading, spacing: 6) { statusBadges }
            }
            Text(bounty.nextAction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { detailMetrics }
                VStack(alignment: .leading, spacing: 8) { detailMetrics }
            }
        }
    }

    @ViewBuilder
    private var detailMetrics: some View {
        DetailSignalPill(title: "Tasks", value: "\(openChecklistCount) open", systemImage: "checklist", tint: openChecklistCount > 0 ? .orange : .green)
        DetailSignalPill(title: "Done", value: "\(completedChecklistCount)", systemImage: "checkmark.circle", tint: .green)
        DetailSignalPill(title: "Work PRs", value: "\(competitorCount)", systemImage: "person.3", tint: competitorCount > 0 ? .orange : .secondary)
    }

    @ViewBuilder
    private var statusBadges: some View {
        StageChip(stage: bounty.managementStage)
        PriorityChip(priority: bounty.userPriority)
        StatusChip(text: bounty.workflowStatus.rawValue, systemImage: bounty.workflowStatus.systemImage, tint: bounty.workflowStatus.tint)
        RiskChip(level: bounty.riskLevel)
        if bounty.isFollowUpDue {
            StatusChip(text: "Due", systemImage: "calendar.badge.exclamationmark", tint: .red)
        }
    }
}

private struct BountySignalDial: View {
    let bounty: Bounty
    let competitorCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: CGFloat {
        CGFloat(min(max(bounty.payoutChance, 0), 100)) / 100
    }

    private var trigger: Date {
        bounty.lastRefreshedAt ?? bounty.updatedAt
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(bounty.riskLevel.tint.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(bounty.riskLevel.tint.opacity(0.12))
                .frame(width: 78, height: 78)
            VStack(spacing: 4) {
                Image(systemName: bounty.workflowStatus.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(bounty.workflowStatus.tint)
                    .symbolEffect(.bounce, value: bounty.workflowStatus.rawValue)
                Text("\(bounty.payoutChance)%")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText())
                if competitorCount > 0 {
                    Text("\(competitorCount) PR")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 132, height: 132)
        .phaseAnimator(reduceMotion ? [0] : [0, 1], trigger: trigger) { content, phase in
            content.scaleEffect(phase == 1 ? 1.035 : 1.0)
        } animation: { phase in
            phase == 1 ? .snappy(duration: 0.24) : .smooth(duration: 0.28)
        }
        .accessibilityLabel("Payout chance \(bounty.payoutChance) percent")
    }
}

private struct DetailSignalPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: 96, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct BountyManagementEditor: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    let bounty: Bounty
    @State private var draftStage: BountyManagementStage = .inbox
    @State private var draftPriority: BountyUserPriority = .normal
    @State private var draftPinned = false
    @State private var hasFollowUp = false
    @State private var draftFollowUp = Date()
    @State private var draftTags = ""
    @State private var draftNotes = ""
    @State private var didLoadDraft = false

    var body: some View {
        Section("Management") {
            HStack(spacing: 8) {
                StageChip(stage: bounty.managementStage)
                PriorityChip(priority: bounty.userPriority)
                if bounty.isPinned {
                    StatusChip(text: "Pinned", systemImage: "star.fill", tint: .yellow)
                }
                if bounty.isFollowUpDue {
                    StatusChip(text: "Due", systemImage: "calendar.badge.exclamationmark", tint: .red)
                }
            }
            .padding(.vertical, 2)

            Toggle(isOn: $draftPinned) {
                Label("Pinned", systemImage: draftPinned ? "star.fill" : "star")
            }

            Picker("Stage", selection: $draftStage) {
                ForEach(BountyManagementStage.allCases) { stage in
                    Label(stage.rawValue, systemImage: stage.systemImage).tag(stage)
                }
            }

            Picker("Priority", selection: $draftPriority) {
                ForEach(BountyUserPriority.allCases) { priority in
                    Label(priority.rawValue, systemImage: priority.systemImage).tag(priority)
                }
            }

            Toggle("Follow up", isOn: $hasFollowUp)
            if hasFollowUp {
                DatePicker("Date", selection: $draftFollowUp, displayedComponents: [.date, .hourAndMinute])
            }

            TextField("Tags, comma separated", text: $draftTags)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextEditor(text: $draftNotes)
                .frame(minHeight: 88)
                .overlay(alignment: .topLeading) {
                    if draftNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Notes, review plan, payout context")
                            .foregroundStyle(.secondary.opacity(0.7))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Button { saveDraft() } label: {
                    Label("Save Management", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                Button("Reset") { loadDraft(force: true) }
                    .buttonStyle(.bordered)
            }
        }
        .onAppear { loadDraft() }
        .onChange(of: bounty.stableID) { _, _ in loadDraft(force: true) }
    }

    private func loadDraft(force: Bool = false) {
        guard force || didLoadDraft == false else { return }
        didLoadDraft = true
        draftStage = bounty.managementStage
        draftPriority = bounty.userPriority
        draftPinned = bounty.isPinned
        hasFollowUp = bounty.followUpAt != nil
        draftFollowUp = bounty.followUpAt ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        draftTags = bounty.userTags.joined(separator: ", ")
        draftNotes = bounty.userNotes
    }

    private func saveDraft() {
        app.saveManagement(
            for: bounty,
            stage: draftStage,
            priority: draftPriority,
            isPinned: draftPinned,
            followUpAt: hasFollowUp ? draftFollowUp : nil,
            notes: draftNotes,
            tags: tags(from: draftTags)
        )
    }
}

private struct BountyChecklistSection: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    let bounty: Bounty
    let items: [BountyChecklistItem]
    @State private var draftTitle = ""

    private var sortedItems: [BountyChecklistItem] {
        items.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return rhs.isDone }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var completedItems: [BountyChecklistItem] { items.filter(\.isDone) }

    var body: some View {
        Section("Checklist") {
            HStack(spacing: 8) {
                TextField("Next step", text: $draftTitle)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit(addItem)
                Button(action: addItem) {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add checklist item")
            }

            if sortedItems.isEmpty {
                Text("Add review, test, maintainer, and payout follow-up tasks for this bounty.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedItems, id: \.stableID) { item in
                    Button {
                        app.toggleChecklistItem(item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                            Text(item.title)
                                .strikethrough(item.isDone)
                                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                            Spacer(minLength: 8)
                            if item.isDone, let completedAt = item.completedAt {
                                Text(completedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { app.deleteChecklistItem(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if completedItems.isEmpty == false {
                Button(role: .destructive) {
                    app.clearCompletedChecklistItems(for: bounty)
                } label: {
                    Label("Clear Completed", systemImage: "checkmark.circle.trianglebadge.exclamationmark")
                }
            }
        }
    }

    private func addItem() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        app.addChecklistItem(title: trimmed, for: bounty, existingCount: items.count)
        draftTitle = ""
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
        ZStack {
            BountyBackdrop()
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
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Competition")
    }
}

private struct DiscoverView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var trackedBounties: [Bounty]
    @AppStorage("defaultMinimumPayout") private var defaultMinimumPayout = 0
    @State private var didApplyDefaultMinimumPayout = false
    @State private var videoFilter: TernaryFilter = .any
    @State private var assignmentFilter: TernaryFilter = .any

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
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
                    Label("Verified Algora only", systemImage: "checkmark.seal")
                    Text("Search results require an algora-pbc[bot] issue comment with a visible bounty amount and claim or attempt flow.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                            let isTracked = trackedIDs.contains(bounty.stableID)
                            VStack(alignment: .leading, spacing: 8) {
                                BountySnapshotRow(snapshot: bounty)
                                HStack(spacing: 8) {
                                    Button(isTracked ? "Tracked" : "Track") { app.trackDiscovered(bounty) }
                                        .buttonStyle(.bordered)
                                        .disabled(isTracked)
                                    if isTracked {
                                        StatusChip(text: "In queue", systemImage: "checkmark.circle", tint: .green)
                                    }
                                }
                            }
                        }
                    }
                }
                }
                .scrollContentBackground(.hidden)
                .refreshable { await app.discover() }
            }
            .navigationTitle("Discover")
            .onAppear {
                guard didApplyDefaultMinimumPayout == false else { return }
                didApplyDefaultMinimumPayout = true
                if app.discoverFilters.minimumPayout == 0 {
                    app.discoverFilters.minimumPayout = defaultMinimumPayout
                }
            }
        }
    }

    private var trackedIDs: Set<String> {
        Set(trackedBounties.map(\.stableID))
    }
}

private struct AlertsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \AlertEvent.createdAt, order: .reverse) private var alerts: [AlertEvent]
    @State private var showUnreadOnly = false

    private var visibleAlerts: [AlertEvent] {
        showUnreadOnly ? alerts.filter { $0.isRead == false } : alerts
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
                List {
                Section {
                    Toggle("Unread only", isOn: $showUnreadOnly)
                    HStack(spacing: 8) {
                        StatusChip(text: "\(alerts.filter { $0.isRead == false }.count) unread", systemImage: "bell.badge", tint: .orange)
                        StatusChip(text: "\(alerts.count) total", systemImage: "bell", tint: .secondary)
                    }
                }
                .listRowBackground(Color.clear)

                if visibleAlerts.isEmpty {
                    ContentUnavailableView(showUnreadOnly ? "No Unread Alerts" : "No Alerts", systemImage: "bell", description: Text("Alerts appear after refresh detects maintainer, check, PR, issue, claim, or payment changes."))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleAlerts, id: \.stableID) { alert in
                        AlertCard(alert: alert)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            .listRowBackground(Color.clear)
                            .swipeActions {
                                Button(alert.isRead ? "Unread" : "Read") {
                                    alert.isRead.toggle()
                                    try? modelContext.save()
                                }
                                Button(role: .destructive) {
                                    modelContext.delete(alert)
                                    try? modelContext.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { app.markAllAlertsRead() } label: {
                            Label("Mark All Read", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) { app.deleteReadAlerts() } label: {
                            Label("Delete Read", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(alerts.isEmpty)
                }
            }
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
    @AppStorage("lastBackgroundRefreshAt") private var lastBackgroundRefreshAt = 0.0
    @AppStorage("notifyMaintainerComments") private var notifyMaintainerComments = true
    @AppStorage("notifyChecks") private var notifyChecks = true
    @AppStorage("notifyPayment") private var notifyPayment = true
    @AppStorage("defaultMinimumPayout") private var defaultMinimumPayout = 0

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
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
                    if lastBackgroundRefreshAt > 0 {
                        LabeledContent("Last Background Refresh", value: Date(timeIntervalSince1970: lastBackgroundRefreshAt).formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("Background refresh has not completed yet. iOS decides when scheduled refresh work runs.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Refresh Diagnostics") {
                    if let updatedAt = app.refreshDiagnostics.updatedAt {
                        if let login = app.refreshDiagnostics.githubLogin {
                            LabeledContent("GitHub User", value: login)
                        }
                        LabeledContent("Last Refresh", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Tracked Algora Bounties", value: "\(app.refreshDiagnostics.trackedBountyCount)")
                        LabeledContent("Checked PRs", value: "\(app.refreshDiagnostics.scannedPullRequestCount)")
                        LabeledContent("Claim Candidates", value: "\(app.refreshDiagnostics.claimPullRequestCount)")
                        LabeledContent("Verified Active Claims", value: "\(app.refreshDiagnostics.activeClaimPullRequestCount)")
                        LabeledContent("Linked Issue Checks", value: "\(app.refreshDiagnostics.linkedIssueCheckCount)")
                        LabeledContent("No Algora Evidence", value: "\(app.refreshDiagnostics.skippedPullRequestCount)")
                        if app.refreshDiagnostics.failedPullRequestCount > 0 {
                            LabeledContent("Failed PRs", value: "\(app.refreshDiagnostics.failedPullRequestCount)")
                        }
                        if app.refreshDiagnostics.warningCount > 0 {
                            LabeledContent("Warnings", value: "\(app.refreshDiagnostics.warningCount)")
                        }
                    } else {
                        Text("No refresh run yet.")
                            .foregroundStyle(.secondary)
                    }
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
                    Text("This clears fetched bounties, PRs, rules, competitors, alerts, checklists, and risk snapshots. Tokens stay in Keychain unless removed above.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                }
                .scrollContentBackground(.hidden)
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
            ZStack {
                BountyBackdrop()
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
                    Text("Manual payout, Gitcoin, crypto wallet, PayPal, BTC, sats, USDC, and generic bounty URLs are excluded. BountyDesk only tracks GitHub issues verified by official Algora evidence with amount and claim flow.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Import Bounty")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if app.addManualURL(urlText) {
                            dismiss()
                        } else {
                            errorMessage = "Not Algora. Excluded: no official Algora evidence / no Algora claim flow."
                        }
                    }
                }
            }
        }
    }
}

private func workPullRequestText(_ count: Int) -> String {
    count == 1 ? "1 work PR" : "\(count) work PRs"
}

private struct BountyRow: View {
    let bounty: Bounty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(bounty.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(bounty.issueSlug)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    if bounty.isPinned {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Pinned")
                    }
                    Text(bounty.payoutText)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { managementChips }
                VStack(alignment: .leading, spacing: 6) { managementChips }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { statusChips }
                VStack(alignment: .leading, spacing: 6) { statusChips }
            }
            BountyProgressRail(level: bounty.riskLevel, chance: bounty.payoutChance)
            Text(bounty.nextAction)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if bounty.userTags.isEmpty == false || bounty.userNotes.isEmpty == false || bounty.followUpAt != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if bounty.userTags.isEmpty == false {
                        TagCloud(tags: Array(bounty.userTags.prefix(4)))
                    }
                    Text(bounty.managementSummary)
                        .font(.caption)
                        .foregroundStyle(bounty.isFollowUpDue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var managementChips: some View {
        StageChip(stage: bounty.managementStage)
        PriorityChip(priority: bounty.userPriority)
        if let followUpAt = bounty.followUpAt {
            StatusChip(
                text: bounty.isFollowUpDue ? "Follow-up due" : followUpAt.formatted(date: .abbreviated, time: .omitted),
                systemImage: bounty.isFollowUpDue ? "calendar.badge.exclamationmark" : "calendar",
                tint: bounty.isFollowUpDue ? .red : .secondary
            )
        }
    }

    @ViewBuilder
    private var statusChips: some View {
        StatusChip(text: bounty.workflowStatus.rawValue, systemImage: bounty.workflowStatus.systemImage, tint: bounty.workflowStatus.tint)
        StatusChip(text: bounty.checkState.rawValue, systemImage: bounty.checkState.systemImage, tint: bounty.checkState.tint)
        RiskChip(level: bounty.riskLevel)
        if bounty.competitionCount > 0 {
            StatusChip(text: workPullRequestText(bounty.competitionCount), systemImage: "person.3", tint: .orange)
        }
    }
}

private struct BountyCompactRow: View {
    let bounty: Bounty

    var body: some View {
        NavigationLink {
            BountyDetailView(bounty: bounty)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                    Text(bounty.title).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 6) {
                        StageChip(stage: bounty.managementStage)
                        PriorityChip(priority: bounty.userPriority)
                        if bounty.competitionCount > 0 {
                            StatusChip(text: workPullRequestText(bounty.competitionCount), systemImage: "person.3", tint: .orange)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(bounty.payoutText)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                    RiskChip(level: bounty.riskLevel)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bountyGlassCard(cornerRadius: 8, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

private struct BountySnapshotRow: View {
    let snapshot: TrackedBountySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.title).font(.headline.weight(.semibold)).lineLimit(2)
                    Text("\(snapshot.repoOwner)/\(snapshot.repoName)#\(snapshot.issueNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(snapshot.amount > 0 ? snapshot.amount.formatted(.currency(code: snapshot.currency).precision(.fractionLength(0))) : "TBD")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
            }
            HStack {
                RiskChip(level: snapshot.riskLevel)
                StatusChip(text: workPullRequestText(snapshot.competitionCount), systemImage: "person.3", tint: snapshot.competitionCount > 0 ? .orange : .secondary)
            }
            Text(snapshot.nextAction).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .bountyGlassCard(cornerRadius: 8)
    }
}

private struct ActionRow: View {
    let bounty: Bounty

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bounty.riskLevel == .high ? "exclamationmark.triangle.fill" : bounty.workflowStatus.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(bounty.riskLevel.tint)
                .frame(width: 32, height: 32)
                .background(bounty.riskLevel.tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(bounty.payoutText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.green)
                }
                Text(bounty.nextAction).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    StageChip(stage: bounty.managementStage)
                    PriorityChip(priority: bounty.userPriority)
                    if bounty.isPinned { StatusChip(text: "Pinned", systemImage: "star.fill", tint: .yellow) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: Circle())
                Spacer()
            }
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: value)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
        .accessibilityElement(children: .combine)
    }
}

private struct SyncBanner: View {
    let message: String
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: warnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(warnings.isEmpty ? .green : .orange)
                .symbolEffect(.bounce, value: warnings.count)
            ForEach(warnings.prefix(3), id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

private struct BountyProgressRail: View {
    let level: RiskLevel
    let chance: Int

    private var normalizedChance: CGFloat {
        CGFloat(min(max(chance, 0), 100)) / 100
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.16))
                Capsule()
                    .fill(level.tint.gradient)
                    .frame(width: max(8, proxy.size.width * normalizedChance))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Payout chance \(chance) percent")
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
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
            .accessibilityLabel(text)
    }
}

private struct RiskChip: View {
    let level: RiskLevel

    var body: some View {
        StatusChip(text: "\(level.rawValue) Risk", systemImage: "gauge.with.dots.needle.67percent", tint: level.tint)
    }
}

private struct StageChip: View {
    let stage: BountyManagementStage

    var body: some View {
        StatusChip(text: stage.rawValue, systemImage: stage.systemImage, tint: stage.tint)
    }
}

private struct PriorityChip: View {
    let priority: BountyUserPriority

    var body: some View {
        StatusChip(text: priority.rawValue, systemImage: priority.systemImage, tint: priority.tint)
    }
}

private struct TagCloud: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tagViews }
            VStack(alignment: .leading, spacing: 6) { tagViews }
        }
    }

    @ViewBuilder
    private var tagViews: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .foregroundStyle(.secondary)
                .background(.secondary.opacity(0.12), in: Capsule())
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

private func priorityRank(_ priority: BountyUserPriority) -> Int {
    switch priority {
    case .urgent: return 4
    case .high: return 3
    case .normal: return 2
    case .low: return 1
    }
}

private func stageRank(_ stage: BountyManagementStage) -> Int {
    switch stage {
    case .focus: return 6
    case .payout: return 5
    case .waiting: return 4
    case .inbox: return 3
    case .done: return 2
    case .archived: return 1
    }
}

private func tags(from text: String) -> [String] {
    text.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
        .uniquedCaseInsensitive()
}

private func dollars(_ amount: Int) -> String {
    amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}

private extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
