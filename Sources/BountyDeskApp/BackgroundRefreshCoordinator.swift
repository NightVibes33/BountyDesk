import Foundation
#if canImport(BackgroundTasks)
@preconcurrency import BackgroundTasks
#endif

@MainActor
final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()
    private let identifier = "com.example.bountydesk.refresh"
    private var didRegister = false
    private var refreshHandler: (() async -> Bool)?

    private init() {}

    private var configuredIntervalMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        return stored == 0 ? 30 : stored
    }

    func configure(refreshHandler: @escaping () async -> Bool) {
        self.refreshHandler = refreshHandler
    }

    func register() {
        #if canImport(BackgroundTasks)
        guard didRegister == false else { return }
        didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { @MainActor in
                BackgroundRefreshCoordinator.shared.handle(task: task as? BGAppRefreshTask)
            }
        }
        #endif
    }

    func scheduleAppRefresh(afterMinutes minutes: Int = 30) {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(min(max(minutes, 15), 240) * 60))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background refresh is opportunistic and may be denied for sideloaded builds.
        }
        #endif
    }

    #if canImport(BackgroundTasks)
    private func handle(task: BGAppRefreshTask?) {
        scheduleAppRefresh(afterMinutes: configuredIntervalMinutes)
        guard let task else { return }
        let refreshTask = Task { @MainActor in
            let success = await runRefreshHandler()
            guard Task.isCancelled == false else { return }
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
    #endif

    private func runRefreshHandler() async -> Bool {
        guard let refreshHandler else { return false }
        return await refreshHandler()
    }
}
