import SwiftUI
import UIKit
#if canImport(CloudKit)
import CloudKit
#endif

@main
struct CodexAlertApp: App {
    @UIApplicationDelegateAdaptor(CodexAlertAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class CodexAlertAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()

        Task {
            await installBackgroundSubscription()
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CodexAlertConfig.cloudKit.isUsable else {
            completionHandler(.noData)
            return
        }

        #if canImport(CloudKit)
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        #endif

        Task {
            do {
                let result = try await AlertSyncService.shared.sync(notifyForNewAlerts: true)
                completionHandler(result.newAlerts.isEmpty ? .noData : .newData)
            } catch {
                completionHandler(.failed)
            }
        }
    }

    private func installBackgroundSubscription() async {
        guard CodexAlertConfig.cloudKit.isUsable else {
            return
        }

        #if canImport(CloudKit)
        do {
            let sync = CloudKitAttentionSync(containerIdentifier: CodexAlertConfig.cloudKit.containerIdentifier)
            try await sync.ensureBackgroundSubscription()
        } catch {
            NSLog("CloudKit background subscription setup failed: %@", error.localizedDescription)
        }
        #endif
    }
}
