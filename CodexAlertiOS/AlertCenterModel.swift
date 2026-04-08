import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AlertCenterModel {
    private(set) var alerts: [AttentionAlert] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private(set) var readAlertIDs: Set<UUID> = []
    private(set) var responsesByAlertID: [UUID: AttentionResponse] = [:]

    private let syncService: AlertSyncService

    init(store: FileAttentionAlertStore) {
        self.syncService = AlertSyncService(store: store)
    }

    func loadCachedAlerts() async {
        do {
            alerts = try await syncService.loadCachedAlerts()
            readAlertIDs = try await syncService.loadReadAlertIDs()
            responsesByAlertID = try await syncService.loadResponses(for: alerts.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            alerts = try await syncService.sync(notifyForNewAlerts: true).alerts
            readAlertIDs = try await syncService.loadReadAlertIDs()
            responsesByAlertID = try await syncService.loadResponses(for: alerts.map(\.id))
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

    func isUnread(_ alert: AttentionAlert) -> Bool {
        !readAlertIDs.contains(alert.id)
    }

    func markAsRead(_ alert: AttentionAlert) async {
        do {
            try await syncService.markAsRead(ids: [alert.id])
            readAlertIDs.insert(alert.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteAlerts(at offsets: IndexSet) async {
        let ids = offsets.map { alerts[$0].id }

        do {
            try await syncService.delete(ids: ids)
            alerts.remove(atOffsets: offsets)
            readAlertIDs.subtract(ids)
            for id in ids {
                responsesByAlertID.removeValue(forKey: id)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func response(for alert: AttentionAlert) -> AttentionResponse? {
        responsesByAlertID[alert.id]
    }

    func submitResponse(_ answer: String, for alert: AttentionAlert) async {
        do {
            let response = try await syncService.submitResponse(
                answer,
                for: alert,
                responder: "Rog"
            )
            responsesByAlertID[alert.id] = response
            try await syncService.markAsRead(ids: [alert.id])
            readAlertIDs.insert(alert.id)
            errorMessage = nil
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
    private let localFallbackDecider: LocalNotificationFallbackDecider

    static let shared = AlertSyncService(
        store: FileAttentionAlertStore(
            directory: URL.documentsDirectory.appending(path: "Alerts", directoryHint: .isDirectory)
        ),
        readStore: AlertReadStateStore(
            fileURL: URL.documentsDirectory.appending(path: "AlertReadState.json")
        ),
        deliveryStore: AlertNotificationDeliveryStore(
            fileURL: URL.documentsDirectory.appending(path: "AlertNotificationDelivery.json")
        ),
        localFallbackDecider: LocalNotificationFallbackDecider()
    )

    private let store: FileAttentionAlertStore
    private let readStore: AlertReadStateStore
    private let deliveryStore: AlertNotificationDeliveryStore

    init(
        store: FileAttentionAlertStore,
        readStore: AlertReadStateStore = AlertReadStateStore(fileURL: URL.documentsDirectory.appending(path: "AlertReadState.json")),
        deliveryStore: AlertNotificationDeliveryStore = AlertNotificationDeliveryStore(fileURL: URL.documentsDirectory.appending(path: "AlertNotificationDelivery.json")),
        localFallbackDecider: LocalNotificationFallbackDecider = LocalNotificationFallbackDecider()
    ) {
        self.store = store
        self.readStore = readStore
        self.deliveryStore = deliveryStore
        self.localFallbackDecider = localFallbackDecider
    }

    func loadCachedAlerts() async throws -> [AttentionAlert] {
        try await store.loadAll()
    }

    func loadReadAlertIDs() async throws -> Set<UUID> {
        try await readStore.load()
    }

    func loadResponses(for alertIDs: [UUID]) async throws -> [UUID: AttentionResponse] {
        #if canImport(CloudKit)
        guard CodexAlertConfig.cloudKit.isUsable else {
            return [:]
        }

        let sync = CloudKitAttentionSync(containerIdentifier: CodexAlertConfig.cloudKit.containerIdentifier)
        return try await sync.fetchResponses(for: alertIDs)
        #else
        return [:]
        #endif
    }

    func registerDeviceToken(
        _ token: Data,
        installationID: String,
        bundleIdentifier: String
    ) async throws {
        #if canImport(CloudKit)
        guard CodexAlertConfig.cloudKit.isUsable else {
            return
        }

        let registration = try AttentionDeviceRegistration(
            id: installationID,
            token: token.map { String(format: "%02x", $0) }.joined(),
            platform: "iOS",
            bundleIdentifier: bundleIdentifier
        )
        let sync = CloudKitAttentionSync(containerIdentifier: CodexAlertConfig.cloudKit.containerIdentifier)
        try await sync.saveDeviceRegistration(registration)
        #endif
    }

    func sync(notifyForNewAlerts: Bool) async throws -> AlertSyncResult {
        var mergedAlerts = try await store.loadAll()
        var newAlerts: [AttentionAlert] = []
        let remotelyDeliveredAlertIDs = try await deliveryStore.load()
        var consumedRemoteDeliveryIDs: [UUID] = []

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
                    if remotelyDeliveredAlertIDs.contains(alert.id) {
                        consumedRemoteDeliveryIDs.append(alert.id)
                    } else {
                        let shouldNotify = try await localFallbackDecider.shouldNotifyLocally(
                            for: alert.id,
                            initiallyDeliveredAlertIDs: remotelyDeliveredAlertIDs,
                            refreshDeliveredAlertIDs: { [deliveryStore] in
                                try await deliveryStore.load()
                            }
                        )

                        if shouldNotify {
                            try await notify(for: alert)
                        } else {
                            consumedRemoteDeliveryIDs.append(alert.id)
                        }
                    }
                }
            }
        }
        #endif

        if !consumedRemoteDeliveryIDs.isEmpty {
            try await deliveryStore.remove(ids: consumedRemoteDeliveryIDs)
        }

        if !newAlerts.isEmpty {
            await MainActor.run {
                NotificationCenter.default.post(name: .attentionAlertsDidChange, object: nil)
            }
        }

        return AlertSyncResult(alerts: mergedAlerts, newAlerts: newAlerts)
    }

    func markAsRead(ids: [UUID]) async throws {
        try await readStore.markAsRead(ids: ids)
    }

    func delete(ids: [UUID]) async throws {
        try await store.delete(ids: ids)
        try await readStore.remove(ids: ids)
        try await deliveryStore.remove(ids: ids)
    }

    func markDeliveredByRemotePush(alertID: UUID) async throws {
        try await deliveryStore.markDelivered(ids: [alertID])
    }

    func submitResponse(
        _ answer: String,
        for alert: AttentionAlert,
        responder: String
    ) async throws -> AttentionResponse {
        #if canImport(CloudKit)
        guard CodexAlertConfig.cloudKit.isUsable else {
            throw AlertResponseError.cloudKitUnavailable
        }

        guard alert.responseOptions?.contains(answer.lowercased()) == true else {
            throw AlertResponseError.invalidAnswer
        }

        let response = AttentionResponse(
            alertID: alert.id,
            answer: answer,
            responder: responder
        )
        let sync = CloudKitAttentionSync(containerIdentifier: CodexAlertConfig.cloudKit.containerIdentifier)
        try await sync.saveResponse(response)
        return response
        #else
        throw AlertResponseError.cloudKitUnavailable
        #endif
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

enum AlertResponseError: LocalizedError {
    case cloudKitUnavailable
    case invalidAnswer

    var errorDescription: String? {
        switch self {
        case .cloudKitUnavailable:
            "This response flow requires CloudKit to be enabled."
        case .invalidAnswer:
            "That answer is not valid for this question."
        }
    }
}

actor AlertReadStateStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> Set<UUID> {
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let ids = try decoder.decode([UUID].self, from: data)
        return Set(ids)
    }

    func markAsRead(ids: [UUID]) throws {
        var existing = try load()
        existing.formUnion(ids)
        try save(existing)
    }

    func remove(ids: [UUID]) throws {
        guard !ids.isEmpty else {
            return
        }

        var existing = try load()
        existing.subtract(ids)
        try save(existing)
    }

    private func save(_ ids: Set<UUID>) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path()) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(Array(ids))
        try data.write(to: fileURL, options: .atomic)
    }
}

actor AlertNotificationDeliveryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> Set<UUID> {
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        let ids = try decoder.decode([UUID].self, from: data)
        return Set(ids)
    }

    func markDelivered(ids: [UUID]) throws {
        var existing = try load()
        existing.formUnion(ids)
        try save(existing)
    }

    func remove(ids: [UUID]) throws {
        guard !ids.isEmpty else {
            return
        }

        var existing = try load()
        existing.subtract(ids)
        try save(existing)
    }

    private func save(_ ids: Set<UUID>) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path()) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(Array(ids))
        try data.write(to: fileURL, options: .atomic)
    }
}
