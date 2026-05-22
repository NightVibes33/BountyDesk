import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

final class BackgroundRefreshCoordinator: @unchecked Sendable {
    static let shared = BackgroundRefreshCoordinator()
    private let identifier = "com.example.bountydesk.refresh"
    private var didRegister = false

    private init() {}

    private var configuredIntervalMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        return stored == 0 ? 30 : stored
    }

    func register() {
        #if canImport(BackgroundTasks)
        guard didRegister == false else { return }
        didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            self?.handle(task: task as? BGAppRefreshTask)
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
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        task.setTaskCompleted(success: true)
    }
    #endif
}
