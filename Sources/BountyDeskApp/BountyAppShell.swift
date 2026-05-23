import SwiftUI

struct MainTabs: View {
    @State private var isShowingSettings = false

    var body: some View {
        TabView {
            TodayView(openSettings: openSettings)
                .tabItem { Label("Today", systemImage: "calendar.badge.clock") }
            BountyListView(openSettings: openSettings)
                .tabItem { Label("Queue", systemImage: "tray.full") }
            DiscoverView(openSettings: openSettings)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            AlertsView(openSettings: openSettings)
                .tabItem { Label("Alerts", systemImage: "bell") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
    }

    private func openSettings() {
        isShowingSettings = true
    }
}

struct SettingsToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }
}
