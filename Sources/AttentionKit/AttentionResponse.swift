import Foundation

public struct AttentionResponse: Codable, Equatable, Sendable {
    public let alertID: UUID
    public let answer: String
    public let responder: String
    public let respondedAt: Date

    public init(
        alertID: UUID,
        answer: String,
        responder: String,
        respondedAt: Date = Date()
    ) {
        self.alertID = alertID
        self.answer = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.responder = responder.trimmingCharacters(in: .whitespacesAndNewlines)
        self.respondedAt = respondedAt
    }
}
