import Foundation
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()
    private let identifier = "com.example.bountydesk.refresh"
    private var didRegister = false

    private init() {}

    func register() {
        #if canImport(BackgroundTasks)
        guard didRegister == false else { return }
        didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            self?.handle(task: task as? BGAppRefreshTask)
        }
        #endif
    }

    func scheduleAppRefresh() {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background refresh is opportunistic and may be denied for sideloaded builds.
        }
        #endif
    }

    #if canImport(BackgroundTasks)
    private func handle(task: BGAppRefreshTask?) {
        scheduleAppRefresh()
        guard let task else { return }
        let work = Task {
            let token = try? KeychainStore().read(.githubToken)
            if let token, token.isEmpty == false {
                _ = try? await GitHubClient().validateToken(token)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
    #endif
}
