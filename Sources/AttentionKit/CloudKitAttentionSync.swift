#if canImport(CloudKit)
import CloudKit
import Foundation

public struct CloudKitAttentionSync: Sendable {
    public static let recordType = "AttentionAlert"
    public static let feedRecordType = "AttentionFeed"
    public static let feedRecordName = "recent-alerts"
    public static let recentRecordNamesKey = "recentRecordNames"
    public static let backgroundSubscriptionID = "attention-feed-background"

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

        return try result
            .compactMap { _, recordResult in
                let record = try recordResult.get()
                return try Self.decode(record)
            }
            .sorted { $0.createdAt > $1.createdAt }
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

        return try AttentionAlert(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            title: title,
            body: body,
            sender: sender,
            urgency: urgency,
            createdAt: record.creationDate ?? .now
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

        var names = feedRecord[Self.recentRecordNamesKey] as? [String] ?? []
        names.removeAll { $0 == recordName }
        names.insert(recordName, at: 0)
        feedRecord[Self.recentRecordNamesKey] = Array(names.prefix(limit))

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
