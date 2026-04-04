import Foundation

public struct AttentionAlert: Codable, Equatable, Identifiable, Sendable {
    public enum Urgency: String, Codable, CaseIterable, Sendable {
        case low
        case normal
        case high
        case critical
    }

    public let id: UUID
    public let title: String
    public let body: String
    public let sender: String
    public let urgency: Urgency
    public let createdAt: Date

    public var notificationTitle: String {
        "\(sender) needs your attention"
    }

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        sender: String,
        urgency: Urgency = .normal,
        createdAt: Date = Date()
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSender = sender.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty else {
            throw AttentionAlertError.emptyTitle
        }

        guard !normalizedBody.isEmpty else {
            throw AttentionAlertError.emptyBody
        }

        guard !normalizedSender.isEmpty else {
            throw AttentionAlertError.emptySender
        }

        self.id = id
        self.title = normalizedTitle
        self.body = normalizedBody
        self.sender = normalizedSender
        self.urgency = urgency
        self.createdAt = createdAt
    }
}

public enum AttentionAlertError: LocalizedError, Equatable {
    case emptyTitle
    case emptyBody
    case emptySender

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Alert title cannot be empty."
        case .emptyBody:
            "Alert body cannot be empty."
        case .emptySender:
            "Alert sender cannot be empty."
        }
    }
}
