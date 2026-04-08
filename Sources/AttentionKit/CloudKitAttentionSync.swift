#if canImport(CloudKit)
import CloudKit
import Foundation

public struct CloudKitAttentionSync: Sendable {
    public static let recordType = "AttentionAlert"
    public static let feedRecordType = "AttentionFeed"
    public static let feedRecordName = "recent-alerts"
    public static let recentRecordNamesKey = "recentRecordNames"
    public static let backgroundSubscriptionID = "attention-feed-background"
    public static let responseRecordType = "AttentionResponse"
    public static let deviceRegistrationRecordType = "AttentionDeviceRegistration"
    public static let deviceRegistrationFeedRecordType = "AttentionDeviceFeed"
    public static let deviceRegistrationFeedRecordName = "registered-devices"
    public static let deviceRegistrationRecordNamesKey = "deviceRecordNames"

    private let database: CKDatabase

    public init(containerIdentifier: String) {
        self.database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    public func ensureBackgroundSubscription() async throws {
        _ = try await database.save(Self.makeBackgroundSubscription())
    }

    public func upload(_ alert: AttentionAlert) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: alert.id.uuidString))
        record["title"] = alert.title
        record["body"] = alert.body
        record["sender"] = alert.sender
        record["urgency"] = alert.urgency.rawValue
        record["taskName"] = alert.taskName
        record["projectName"] = alert.projectName
        record["type"] = alert.type.rawValue
        record["responseOptions"] = alert.responseOptions
        _ = try await database.save(record)

        try await updateFeed(with: alert.id.uuidString)
    }

    public func fetchRecent(limit: Int = 50) async throws -> [AttentionAlert] {
        let feedRecordID = CKRecord.ID(recordName: Self.feedRecordName)

        guard let feedRecord = try? await database.record(for: feedRecordID) else {
            return []
        }

        let recordNames = (feedRecord[Self.recentRecordNamesKey] as? [String] ?? [])
            .prefix(limit)

        guard !recordNames.isEmpty else {
            return []
        }

        let recordIDs = recordNames.map { CKRecord.ID(recordName: $0) }
        let result = try await database.records(for: recordIDs)

        return Self.decodeAlertsSkippingInvalidRecords(result)
    }

    public func saveResponse(_ response: AttentionResponse) async throws {
        let record = CKRecord(
            recordType: Self.responseRecordType,
            recordID: CKRecord.ID(recordName: Self.responseRecordName(for: response.alertID))
        )
        record["alertID"] = response.alertID.uuidString
        record["answer"] = response.answer
        record["responder"] = response.responder
        record["respondedAt"] = response.respondedAt
        _ = try await database.save(record)
    }

    public func fetchResponse(for alertID: UUID) async throws -> AttentionResponse? {
        let recordID = CKRecord.ID(recordName: Self.responseRecordName(for: alertID))
        guard let record = try? await database.record(for: recordID) else {
            return nil
        }
        return try Self.decodeResponse(record)
    }

    public func fetchResponses(for alertIDs: [UUID]) async throws -> [UUID: AttentionResponse] {
        guard !alertIDs.isEmpty else {
            return [:]
        }

        let recordIDs = alertIDs.map { CKRecord.ID(recordName: Self.responseRecordName(for: $0)) }
        let result = try await database.records(for: recordIDs)

        var responses: [UUID: AttentionResponse] = [:]
        for (_, recordResult) in result {
            guard let record = try? recordResult.get(),
                  let response = try? Self.decodeResponse(record) else {
                continue
            }
            responses[response.alertID] = response
        }
        return responses
    }

    public func saveDeviceRegistration(_ registration: AttentionDeviceRegistration) async throws {
        let record = CKRecord(
            recordType: Self.deviceRegistrationRecordType,
            recordID: CKRecord.ID(recordName: Self.deviceRegistrationRecordName(for: registration.id))
        )
        record["token"] = registration.token
        record["platform"] = registration.platform
        record["bundleIdentifier"] = registration.bundleIdentifier
        record["createdAt"] = registration.createdAt
        record["updatedAt"] = registration.updatedAt
        _ = try await database.save(record)

        try await updateDeviceRegistrationFeed(with: record.recordID.recordName)
    }

    public func fetchDeviceRegistrations(limit: Int = 10) async throws -> [AttentionDeviceRegistration] {
        let feedRecordID = CKRecord.ID(recordName: Self.deviceRegistrationFeedRecordName)

        guard let feedRecord = try? await database.record(for: feedRecordID) else {
            return []
        }

        let recordNames = (feedRecord[Self.deviceRegistrationRecordNamesKey] as? [String] ?? [])
            .prefix(limit)

        guard !recordNames.isEmpty else {
            return []
        }

        let recordIDs = recordNames.map { CKRecord.ID(recordName: $0) }
        let result = try await database.records(for: recordIDs)

        return try result
            .compactMap { _, recordResult in
                let record = try recordResult.get()
                return try Self.decodeDeviceRegistration(record)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func deleteAlerts(ids: [UUID]) async throws {
        guard !ids.isEmpty else {
            return
        }

        for id in ids {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: id.uuidString))
        }

        try await removeFromFeed(recordNames: ids.map(\.uuidString))
    }

    private static func decode(_ record: CKRecord) throws -> AttentionAlert {
        guard
            let title = record["title"] as? String,
            let body = record["body"] as? String,
            let sender = record["sender"] as? String,
            let urgencyRawValue = record["urgency"] as? String,
            let urgency = AttentionAlert.Urgency(rawValue: urgencyRawValue)
        else {
            throw CloudKitAttentionSyncError.invalidRecord
        }

        let type = AttentionAlert.AlertType(rawValue: record["type"] as? String ?? "") ?? .info

        return try AttentionAlert(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            title: title,
            body: body,
            sender: sender,
            urgency: urgency,
            taskName: record["taskName"] as? String,
            projectName: record["projectName"] as? String,
            type: type,
            responseOptions: record["responseOptions"] as? [String],
            createdAt: record.creationDate ?? .now
        )
    }

    private static func decodeResponse(_ record: CKRecord) throws -> AttentionResponse {
        guard
            let alertIDRawValue = record["alertID"] as? String,
            let alertID = UUID(uuidString: alertIDRawValue),
            let answer = record["answer"] as? String,
            let responder = record["responder"] as? String
        else {
            throw CloudKitAttentionSyncError.invalidRecord
        }

        let respondedAt = record["respondedAt"] as? Date ?? record.modificationDate ?? .now
        return AttentionResponse(
            alertID: alertID,
            answer: answer,
            responder: responder,
            respondedAt: respondedAt
        )
    }

    private static func decodeDeviceRegistration(_ record: CKRecord) throws -> AttentionDeviceRegistration {
        guard
            let token = record["token"] as? String,
            let platform = record["platform"] as? String,
            let bundleIdentifier = record["bundleIdentifier"] as? String
        else {
            throw CloudKitAttentionSyncError.invalidRecord
        }

        return try AttentionDeviceRegistration(
            id: record.recordID.recordName.replacingOccurrences(of: "device-", with: ""),
            token: token,
            platform: platform,
            bundleIdentifier: bundleIdentifier,
            createdAt: record["createdAt"] as? Date ?? record.creationDate ?? .now,
            updatedAt: record["updatedAt"] as? Date ?? record.modificationDate ?? .now
        )
    }

    private func updateFeed(with recordName: String, limit: Int = 50) async throws {
        let feedRecordID = CKRecord.ID(recordName: Self.feedRecordName)
        let feedRecord: CKRecord

        if let existingRecord = try? await database.record(for: feedRecordID) {
            feedRecord = existingRecord
        } else {
            feedRecord = CKRecord(recordType: Self.feedRecordType, recordID: feedRecordID)
        }

        let names = feedRecord[Self.recentRecordNamesKey] as? [String] ?? []
        feedRecord[Self.recentRecordNamesKey] = Self.updatedRecordNames(
            from: names,
            prepending: recordName,
            limit: limit
        )

        _ = try await database.save(feedRecord)
    }

    private func removeFromFeed(recordNames: [String]) async throws {
        let feedRecordID = CKRecord.ID(recordName: Self.feedRecordName)
        guard let feedRecord = try? await database.record(for: feedRecordID) else {
            return
        }

        let names = feedRecord[Self.recentRecordNamesKey] as? [String] ?? []
        let updatedNames = recordNames.reduce(names) { partialResult, recordName in
            Self.updatedRecordNames(from: partialResult, removing: recordName, limit: 50)
        }
        feedRecord[Self.recentRecordNamesKey] = updatedNames
        _ = try await database.save(feedRecord)
    }

    private func updateDeviceRegistrationFeed(with recordName: String, limit: Int = 10) async throws {
        let feedRecordID = CKRecord.ID(recordName: Self.deviceRegistrationFeedRecordName)
        let feedRecord: CKRecord

        if let existingRecord = try? await database.record(for: feedRecordID) {
            feedRecord = existingRecord
        } else {
            feedRecord = CKRecord(recordType: Self.deviceRegistrationFeedRecordType, recordID: feedRecordID)
        }

        var names = feedRecord[Self.deviceRegistrationRecordNamesKey] as? [String] ?? []
        names.removeAll { $0 == recordName }
        names.insert(recordName, at: 0)
        feedRecord[Self.deviceRegistrationRecordNamesKey] = Array(names.prefix(limit))

        _ = try await database.save(feedRecord)
    }

    public static func makeBackgroundSubscription() -> CKQuerySubscription {
        let subscription = CKQuerySubscription(
            recordType: feedRecordType,
            predicate: NSPredicate(value: true),
            subscriptionID: backgroundSubscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        return subscription
    }

    public static func responseRecordName(for alertID: UUID) -> String {
        "response-\(alertID.uuidString)"
    }

    public static func deviceRegistrationRecordName(for registrationID: String) -> String {
        "device-\(registrationID)"
    }

    public static func updatedRecordNames(
        from existingNames: [String],
        prepending recordName: String,
        limit: Int
    ) -> [String] {
        var names = existingNames
        names.removeAll { $0 == recordName }
        names.insert(recordName, at: 0)
        return Array(names.prefix(limit))
    }

    public static func updatedRecordNames(
        from existingNames: [String],
        removing recordName: String,
        limit: Int
    ) -> [String] {
        Array(existingNames.filter { $0 != recordName }.prefix(limit))
    }

    public static func decodeAlertsSkippingInvalidRecords(
        _ result: [CKRecord.ID: Result<CKRecord, any Error>]
    ) -> [AttentionAlert] {
        result
            .compactMap { _, recordResult -> AttentionAlert? in
                guard let record = try? recordResult.get() else {
                    return nil
                }

                return try? Self.decode(record)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

public enum CloudKitAttentionSyncError: LocalizedError {
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .invalidRecord:
            "CloudKit returned an alert record with missing fields."
        }
    }
}
#endif
