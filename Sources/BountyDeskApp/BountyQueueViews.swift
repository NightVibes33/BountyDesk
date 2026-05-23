import SwiftData
import SwiftUI

struct BountyListView: View {
    var openSettings: () -> Void = {}
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
                    SettingsToolbarButton(action: openSettings)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import bounty URL")
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
        .bountyContentCard(cornerRadius: 8)
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

struct BountyManagementPanel: View {
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
        .bountyContentCard(cornerRadius: 8)
    }
}

struct StagePipeline: View {
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

struct StageCountPill: View {
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

struct ManagementMetric: View {
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
