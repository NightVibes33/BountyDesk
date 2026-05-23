import SwiftData
import SwiftUI

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
