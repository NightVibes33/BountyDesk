import SwiftData
import SwiftUI

struct TodayView: View {
    var openSettings: () -> Void = {}
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
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton(action: openSettings)
                }
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

struct TodayHero: View {
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

struct TodayBountyGroup: View {
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

struct AlertCard: View {
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
        .bountyContentCard(cornerRadius: 8)
    }
}
