import Foundation

public struct APNsPushConfiguration: Equatable, Sendable {
    public let keyID: String
    public let teamID: String
    public let keyPath: String
    public let topic: String
    public let useSandbox: Bool

    public init(
        keyID: String,
        teamID: String,
        keyPath: String,
        topic: String,
        useSandbox: Bool = false
    ) {
        self.keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teamID = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.keyPath = keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.useSandbox = useSandbox
    }

    public var isUsable: Bool {
        !keyID.isEmpty && !teamID.isEmpty && !keyPath.isEmpty && !topic.isEmpty
    }

    public var host: String {
        useSandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com"
    }

    public static func fromEnvironment(
        _ environment: [String: String],
        defaultTopic: String
    ) -> APNsPushConfiguration {
        APNsPushConfiguration(
            keyID: environment["CODEX_ALERT_APNS_KEY_ID"] ?? "",
            teamID: environment["CODEX_ALERT_APNS_TEAM_ID"] ?? "",
            keyPath: environment["CODEX_ALERT_APNS_KEY_PATH"] ?? "",
            topic: environment["CODEX_ALERT_APNS_TOPIC"] ?? defaultTopic,
            useSandbox: (environment["CODEX_ALERT_APNS_USE_SANDBOX"] ?? "").lowercased() == "true"
        )
    }
}
