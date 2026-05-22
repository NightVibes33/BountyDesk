import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Desk", systemImage: "rectangle.grid.2x2") }
            BountyListView()
                .tabItem { Label("Bounties", systemImage: "tray.full") }
            PipelineView()
                .tabItem { Label("Pipeline", systemImage: "point.3.connected.trianglepath.dotted") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var store: BountyStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overviewGrid
                    priorityQueue
                    riskBoard
                }
                .padding(16)
            }
            .background(deskBackground)
            .navigationTitle("BountyDesk")
        }
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Open Value", value: store.totalOpenValue.formatted(.currency(code: "USD").precision(.fractionLength(0))), systemImage: "dollarsign.circle")
            MetricCard(title: "Tracked", value: "\(store.bounties.count)", systemImage: "number.circle")
            MetricCard(title: "Blocked", value: "\(store.blockedCount)", systemImage: "exclamationmark.triangle")
            MetricCard(title: "Paid", value: store.paidValue.formatted(.currency(code: "USD").precision(.fractionLength(0))), systemImage: "checkmark.seal")
        }
    }

    private var priorityQueue: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Priority Queue", subtitle: "Highest value active work")
            ForEach(store.activeBounties.sorted(by: prioritySort).prefix(4)) { bounty in
                BountyRow(bounty: bounty)
            }
        }
        .deskPanel()
    }

    private var riskBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Risk Signals", subtitle: "Competition and blocked work")
            ForEach(store.activeBounties.sorted { $0.riskScore > $1.riskScore }.prefix(3)) { bounty in
                HStack(spacing: 12) {
                    Image(systemName: "person.3.sequence")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bounty.issueSlug)
                            .font(.subheadline.weight(.semibold))
                        Text("\(bounty.competitionCount) competing PRs · \(bounty.checkSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(bounty.riskScore)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .deskControl()
                }
            }
        }
        .deskPanel()
    }

    private func prioritySort(_ lhs: Bounty, _ rhs: Bounty) -> Bool {
        if lhs.priority.rank == rhs.priority.rank { return lhs.amount > rhs.amount }
        return lhs.priority.rank < rhs.priority.rank
    }
}

private struct BountyListView: View {
    @EnvironmentObject private var store: BountyStore
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                filters
                    .listRowBackground(Color.clear)
                ForEach(store.filteredBounties) { bounty in
                    NavigationLink(value: bounty.id) {
                        BountyRow(bounty: bounty)
                    }
                }
                .onDelete(perform: store.delete)
            }
            .searchable(text: $store.searchText, prompt: "Repo, title, labels, notes")
            .navigationTitle("Bounties")
            .navigationDestination(for: UUID.self) { id in
                if let bounty = store.bounties.first(where: { $0.id == id }) {
                    BountyDetailView(bounty: bounty)
                } else {
                    ContentUnavailableView("Missing Bounty", systemImage: "questionmark.folder")
                }
            }
            .toolbar {
                Button { isAdding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add bounty")
            }
            .sheet(isPresented: $isAdding) {
                AddBountyView()
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Status", selection: Binding(
                get: { store.selectedStatus },
                set: { store.selectedStatus = $0 }
            )) {
                Text("All").tag(nil as BountyStatus?)
                ForEach(BountyStatus.allCases) { status in
                    Text(status.rawValue).tag(status as BountyStatus?)
                }
            }
            .pickerStyle(.menu)

            Picker("Priority", selection: Binding(
                get: { store.selectedPriority },
                set: { store.selectedPriority = $0 }
            )) {
                Text("All Priorities").tag(nil as BountyPriority?)
                ForEach(BountyPriority.allCases) { priority in
                    Text(priority.rawValue).tag(priority as BountyPriority?)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 8)
    }
}

private struct PipelineView: View {
    @EnvironmentObject private var store: BountyStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(BountyStatus.allCases) { status in
                    let items = store.bounties.filter { $0.status == status }
                    if items.isEmpty == false {
                        Section {
                            ForEach(items.sorted { $0.priority.rank < $1.priority.rank }) { bounty in
                                NavigationLink(value: bounty.id) {
                                    BountyRow(bounty: bounty)
                                }
                            }
                        } header: {
                            Label("\(status.rawValue) · \(items.count)", systemImage: status.systemImage)
                        }
                    }
                }
            }
            .navigationTitle("Pipeline")
            .navigationDestination(for: UUID.self) { id in
                if let bounty = store.bounties.first(where: { $0.id == id }) {
                    BountyDetailView(bounty: bounty)
                }
            }
        }
    }
}

private struct BountyDetailView: View {
    @EnvironmentObject private var store: BountyStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Bounty

    init(bounty: Bounty) {
        _draft = State(initialValue: bounty)
    }

    var body: some View {
        Form {
            Section("Work") {
                TextField("Title", text: $draft.title)
                TextField("Owner", text: $draft.repoOwner)
                    .textInputAutocapitalization(.never)
                TextField("Repo", text: $draft.repoName)
                    .textInputAutocapitalization(.never)
                Stepper("Issue #\(draft.issueNumber)", value: $draft.issueNumber, in: 1...999_999)
            }

            Section("Bounty") {
                Picker("Status", selection: $draft.status) {
                    ForEach(BountyStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Priority", selection: $draft.priority) {
                    ForEach(BountyPriority.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Payout \(draft.payoutText)", value: $draft.amount, in: 0...100_000, step: 5)
                Stepper("Competition \(draft.competitionCount)", value: $draft.competitionCount, in: 0...500)
                TextField("Checks", text: $draft.checkSummary)
            }

            Section("Links") {
                Link("GitHub Issue", destination: draft.githubIssueURL)
                Link("Algora Page", destination: draft.algoraIssueURL)
                if let prURL = draft.prURL {
                    Link("Pull Request", destination: prURL)
                }
                TextField("PR URL", text: Binding(
                    get: { draft.prURL?.absoluteString ?? "" },
                    set: { value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.prURL = trimmed.isEmpty ? nil : URL(string: trimmed)
                    }
                ))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            }

            Section("Notes") {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle(draft.issueSlug)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.update(draft)
                    dismiss()
                }
            }
        }
    }
}

private struct AddBountyView: View {
    @EnvironmentObject private var store: BountyStore
    @Environment(\.dismiss) private var dismiss
    @State private var issueURL = ""
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub Issue") {
                    TextField("https://github.com/org/repo/issues/123", text: $issueURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if errorMessage.isEmpty == false {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                Section("What gets created") {
                    Text("BountyDesk stores the issue locally, generates the matching Algora page link, and lets you fill payout, PR, status, checks, competition, and notes after triage.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Bounty")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if store.addFromGitHubURL(issueURL) {
                            dismiss()
                        } else {
                            errorMessage = "Enter a GitHub issue or pull request URL."
                        }
                    }
                }
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: BountyStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Storage") {
                    Text("BountyDesk is local-first. Records are stored in this app sandbox so it works when sideloaded with SideStore.")
                    Button("Reload Sample Bounties", role: .destructive) {
                        store.resetSamples()
                    }
                }
                Section("Tracking Model") {
                    Label("Algora page links are generated from GitHub issue URLs", systemImage: "link")
                    Label("Use statuses to separate watching, claimed, submitted, review, merged, paid, and blocked work", systemImage: "flag")
                    Label("Competition and check summaries help rank risk", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct BountyRow: View {
    let bounty: Bounty

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(bounty.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(bounty.payoutText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.green)
            }
            HStack(spacing: 8) {
                Label(bounty.issueSlug, systemImage: "number")
                Spacer()
                Label(bounty.status.rawValue, systemImage: bounty.status.systemImage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                PriorityPill(priority: bounty.priority)
                Text("\(bounty.competitionCount) competing")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: .capsule)
                Text(bounty.checkSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .deskPanel(cornerRadius: 16)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PriorityPill: View {
    let priority: BountyPriority

    var body: some View {
        Text(priority.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(priority == .high ? .red : priority == .medium ? .orange : .secondary)
            .background(.thinMaterial, in: .capsule)
    }
}

private var deskBackground: some View {
    LinearGradient(
        colors: [Color.green.opacity(0.14), Color.blue.opacity(0.12), Color.clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
}
