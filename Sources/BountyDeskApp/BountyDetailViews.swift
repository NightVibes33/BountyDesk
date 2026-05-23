import SwiftData
import SwiftUI

struct BountyDetailView: View {
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
                LabeledContent("Open Claim PRs", value: "\(bounty.openClaimPrs)")
                LabeledContent("Algora Attempts", value: "\(bounty.totalAttemptsFromAlgoraTable)")
                LabeledContent("Reward Links Seen", value: "\(bounty.rewardedClaims)")
                LabeledContent("Competition", value: bounty.competitionLevel.label)
                LabeledContent("Recommendation", value: bounty.recommendation.label)
                LabeledContent("Last Checked", value: bounty.lastRefreshedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not checked")
                LabeledContent("Risk", value: "\(bounty.riskLevel.rawValue) · \(bounty.payoutChance)%")
                LabeledContent("Next Action", value: bounty.nextAction)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { summaryChips }
                    VStack(alignment: .leading, spacing: 6) { summaryChips }
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
                    Text(issue.latestBotComment.isEmpty ? "No official Algora issue comment cached." : issue.latestBotComment)
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

    @ViewBuilder
    private var summaryChips: some View {
        StatusChip(text: "Verified Algora", systemImage: "checkmark.seal", tint: .green)
        StatusChip(text: bounty.workflowStatus.rawValue, systemImage: bounty.workflowStatus.systemImage, tint: .blue)
        StatusChip(text: bounty.competitionLevel.label, systemImage: "person.3", tint: bounty.competitionLevel.tint)
        StatusChip(text: bounty.recommendation.label, systemImage: bounty.recommendation.systemImage, tint: bounty.recommendation.tint)
        RiskChip(level: bounty.riskLevel)
    }
}

struct BountyManagementEditor: View {
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

struct BountyChecklistSection: View {
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

struct CompetitionView: View {
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
                                StatusChip(text: pr.claimSeen ? "Claim Seen" : "No Claim", systemImage: pr.claimSeen ? "checkmark.seal" : "xmark.seal", tint: pr.claimSeen ? .green : .secondary)
                                if pr.rewardSeen { StatusChip(text: "Reward Seen", systemImage: "banknote", tint: .purple) }
                                if pr.serious { StatusChip(text: "Serious", systemImage: "scope", tint: .orange) }
                            }
                            LabeledContent("Checks", value: pr.checksSummary.isEmpty ? pr.checkState.rawValue : pr.checksSummary)
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
