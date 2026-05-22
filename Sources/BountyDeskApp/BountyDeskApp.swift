import SwiftUI

@main
struct BountyDeskApp: App {
    @StateObject private var store = BountyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
