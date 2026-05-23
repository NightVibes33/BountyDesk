import SwiftData
import SwiftUI

struct DiscoverView: View {
    var openSettings: () -> Void = {}
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
                        Label(app.isDiscovering ? "Searching" : "Search Verified Bounties", systemImage: "magnifyingglass")
                    }
                    .disabled(app.isDiscovering)
                }

                Section("Results") {
                    if app.discoveredBounties.isEmpty {
                        ContentUnavailableView("No Verified Bounties", systemImage: "magnifyingglass", description: Text("Search live GitHub issue comments for Algora-hosted bounties with amount and claim flow."))
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
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton(action: openSettings)
                }
            }
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

struct AlertsView: View {
    var openSettings: () -> Void = {}
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
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton(action: openSettings)
                }
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

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false

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

                Section("Onboarding") {
                    Button { hasCompletedFirstRunOnboarding = false } label: {
                        Label("Replay First Run Onboarding", systemImage: "sparkle.magnifyingglass")
                    }
                    Text("The onboarding appears before GitHub setup on a signed-out launch.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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

struct AddBountyView: View {
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
                    Text("Manual payout, Gitcoin, crypto wallet, PayPal, BTC, sats, USDC, and generic bounty URLs are excluded. BountyDesk only tracks GitHub issues verified by an Algora issue comment with amount and claim flow.")
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
                            errorMessage = "Not Algora. Excluded: no Algora issue comment / no Algora claim flow."
                        }
                    }
                }
            }
        }
    }
}
