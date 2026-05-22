import Foundation

@MainActor
final class BountyStore: ObservableObject {
    @Published var bounties: [Bounty] = [] {
        didSet { save() }
    }
    @Published var searchText = ""
    @Published var selectedStatus: BountyStatus?
    @Published var selectedPriority: BountyPriority?

    private let storageKey = "bountydesk.bounties.v1"

    init() {
        load()
    }

    var filteredBounties: [Bounty] {
        bounties
            .filter(matchesFilters)
            .sorted { lhs, rhs in
                if lhs.status == rhs.status {
                    if lhs.priority.rank == rhs.priority.rank { return lhs.updatedAt > rhs.updatedAt }
                    return lhs.priority.rank < rhs.priority.rank
                }
                return statusRank(lhs.status) < statusRank(rhs.status)
            }
    }

    var activeBounties: [Bounty] {
        bounties.filter { ![BountyStatus.paid, BountyStatus.skipped].contains($0.status) }
    }

    var totalOpenValue: Int {
        activeBounties.reduce(0) { $0 + $1.amount }
    }

    var paidValue: Int {
        bounties.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
    }

    var blockedCount: Int {
        bounties.filter { $0.status == .blocked }.count
    }

    func add(_ bounty: Bounty) {
        bounties.insert(bounty, at: 0)
    }

    func update(_ bounty: Bounty) {
        guard let index = bounties.firstIndex(where: { $0.id == bounty.id }) else { return }
        var changed = bounty
        changed.updatedAt = Date()
        bounties[index] = changed
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { filteredBounties[$0].id }
        bounties.removeAll { ids.contains($0.id) }
    }

    func resetSamples() {
        bounties = Bounty.samples
    }

    func addFromGitHubURL(_ text: String) -> Bool {
        guard let bounty = Bounty.fromGitHubURL(text) else { return false }
        add(bounty)
        return true
    }

    private func matchesFilters(_ bounty: Bounty) -> Bool {
        if let selectedStatus, bounty.status != selectedStatus { return false }
        if let selectedPriority, bounty.priority != selectedPriority { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return true }
        return bounty.title.lowercased().contains(query)
            || bounty.repoSlug.lowercased().contains(query)
            || bounty.labels.joined(separator: " ").lowercased().contains(query)
            || bounty.notes.lowercased().contains(query)
    }

    private func statusRank(_ status: BountyStatus) -> Int {
        BountyStatus.allCases.firstIndex(of: status) ?? 0
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            bounties = Bounty.samples
            return
        }
        do {
            bounties = try JSONDecoder().decode([Bounty].self, from: data)
        } catch {
            bounties = Bounty.samples
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bounties) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
