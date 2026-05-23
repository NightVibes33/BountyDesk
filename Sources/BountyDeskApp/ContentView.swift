import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Query(sort: \WatchedOrg.handle) private var watchedOrgs: [WatchedOrg]
    @Query(sort: \Bounty.updatedAt, order: .reverse) private var bounties: [Bounty]
    @AppStorage("hasCompletedFirstRunOnboarding") private var hasCompletedFirstRunOnboarding = false
    @State private var didRestore = false

    var body: some View {
        Group {
            if app.isAuthenticated {
                MainTabs()
            } else if hasCompletedFirstRunOnboarding {
                LoginView()
            } else {
                BountyOnboardingView {
                    hasCompletedFirstRunOnboarding = true
                }
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
