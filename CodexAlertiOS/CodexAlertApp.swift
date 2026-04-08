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
    private let installationID = InstallationIDStore.installationID

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
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            do {
                try await AlertSyncService.shared.registerDeviceToken(
                    deviceToken,
                    installationID: installationID,
                    bundleIdentifier: Bundle.main.bundleIdentifier ?? "net.hatbat.CodexAlert"
                )
            } catch {
                NSLog("APNs device registration upload failed: %@", error.localizedDescription)
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        NSLog("APNs device registration failed: %@", error.localizedDescription)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let alertID = Self.directAlertID(from: userInfo) {
            Task {
                do {
                    try await AlertSyncService.shared.markDeliveredByRemotePush(alertID: alertID)
                    let result = try await AlertSyncService.shared.sync(notifyForNewAlerts: true)
                    completionHandler(result.newAlerts.isEmpty ? .noData : .newData)
                } catch {
                    completionHandler(.failed)
                }
            }
            return
        }

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

    private static func directAlertID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let rawValue = userInfo["alertID"] as? String else {
            return nil
        }

        return UUID(uuidString: rawValue)
    }
}

private enum InstallationIDStore {
    private static let key = "CodexAlertInstallationID"

    static var installationID: String {
        let defaults = UserDefaults.standard

        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let newValue = UUID().uuidString
        defaults.set(newValue, forKey: key)
        return newValue
    }
}
