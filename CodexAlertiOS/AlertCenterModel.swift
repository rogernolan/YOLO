import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AlertCenterModel {
    private(set) var alerts: [AttentionAlert] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let syncService: AlertSyncService

    init(store: FileAttentionAlertStore) {
        self.syncService = AlertSyncService(store: store)
    }

    func loadCachedAlerts() async {
        do {
            alerts = try await syncService.loadCachedAlerts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            alerts = try await syncService.sync(notifyForNewAlerts: true).alerts
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestNotifications() async {
        do {
            let center = UNUserNotificationCenter.current()
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AlertSyncResult {
    let alerts: [AttentionAlert]
    let newAlerts: [AttentionAlert]
}

extension Notification.Name {
    static let attentionAlertsDidChange = Notification.Name("attentionAlertsDidChange")
}

actor AlertSyncService {
    static let shared = AlertSyncService(
        store: FileAttentionAlertStore(
            directory: URL.documentsDirectory.appending(path: "Alerts", directoryHint: .isDirectory)
        )
    )

    private let store: FileAttentionAlertStore

    init(store: FileAttentionAlertStore) {
        self.store = store
    }

    func loadCachedAlerts() async throws -> [AttentionAlert] {
        try await store.loadAll()
    }

    func sync(notifyForNewAlerts: Bool) async throws -> AlertSyncResult {
        var mergedAlerts = try await store.loadAll()
        var newAlerts: [AttentionAlert] = []

        #if canImport(CloudKit)
        if CodexAlertConfig.cloudKit.isUsable {
            let sync = CloudKitAttentionSync(containerIdentifier: CodexAlertConfig.cloudKit.containerIdentifier)
            try await sync.ensureBackgroundSubscription()

            let remoteAlerts = try await sync.fetchRecent()
            let existingIDs = Set(mergedAlerts.map(\.id))
            newAlerts = remoteAlerts.filter { !existingIDs.contains($0.id) }

            for alert in newAlerts {
                try await store.save(alert)
            }

            mergedAlerts = try await store.loadAll()

            if notifyForNewAlerts {
                for alert in newAlerts {
                    try await notify(for: alert)
                }
            }
        }
        #endif

        if !newAlerts.isEmpty {
            await MainActor.run {
                NotificationCenter.default.post(name: .attentionAlertsDidChange, object: nil)
            }
        }

        return AlertSyncResult(alerts: mergedAlerts, newAlerts: newAlerts)
    }

    private func notify(for alert: AttentionAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.notificationTitle
        content.subtitle = alert.title
        content.body = alert.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: alert.id.uuidString,
            content: content,
            trigger: nil
        )

        try await UNUserNotificationCenter.current().add(request)
    }
}
