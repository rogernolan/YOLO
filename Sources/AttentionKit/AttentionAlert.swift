import Foundation

public struct AttentionAlert: Codable, Equatable, Identifiable, Sendable {
    public enum Urgency: String, Codable, CaseIterable, Sendable {
        case low
        case normal
        case high
        case critical
    }

    public enum AlertType: String, Codable, CaseIterable, Sendable {
        case blocked
        case decision
        case approval
        case review
        case info
    }

    public let id: UUID
    public let title: String
    public let body: String
    public let sender: String
    public let urgency: Urgency
    public let taskName: String?
    public let projectName: String?
    public let type: AlertType
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case sender
        case urgency
        case taskName
        case projectName
        case type
        case createdAt
    }

    public var notificationTitle: String {
        "\(sender) needs your attention"
    }

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        sender: String,
        urgency: Urgency = .normal,
        taskName: String? = nil,
        projectName: String? = nil,
        type: AlertType = .info,
        createdAt: Date = Date()
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSender = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTaskName = taskName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines)

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
        self.taskName = normalizedTaskName?.isEmpty == false ? normalizedTaskName : nil
        self.projectName = normalizedProjectName?.isEmpty == false ? normalizedProjectName : nil
        self.type = type
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.body = try container.decode(String.self, forKey: .body)
        self.sender = try container.decode(String.self, forKey: .sender)
        self.urgency = try container.decode(Urgency.self, forKey: .urgency)
        self.taskName = try container.decodeIfPresent(String.self, forKey: .taskName)
        self.projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        self.type = try container.decodeIfPresent(AlertType.self, forKey: .type) ?? .info
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
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
