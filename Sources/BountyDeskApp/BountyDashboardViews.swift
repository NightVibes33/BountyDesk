import SwiftData
import SwiftUI

struct DashboardView: View {
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
                                    .bountyContentCard(cornerRadius: 8)
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

struct DashboardHero: View {
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

struct BountyOrbitGraphic: View {
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

struct EmptyStatePanel: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .frame(maxWidth: .infinity)
            .padding(12)
            .bountyContentCard(cornerRadius: 8)
    }
}
