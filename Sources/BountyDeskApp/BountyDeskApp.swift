import SwiftData
import SwiftUI

@main
struct BountyDeskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = BountyTrackerViewModel()

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            UserAccount.self,
            WatchedOrg.self,
            Bounty.self,
            Claim.self,
            PullRequest.self,
            GitHubIssue.self,
            RepoRuleSet.self,
            CompetitorPR.self,
            AlertEvent.self,
            RiskScoreSnapshot.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create BountyDesk SwiftData container: \(error)")
        }
    }()

    init() {
        BackgroundRefreshCoordinator.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.resumeGitHubDeviceLoginIfNeeded() }
            }
            if phase == .background {
                BackgroundRefreshCoordinator.shared.scheduleAppRefresh()
            }
        }
    }
}
