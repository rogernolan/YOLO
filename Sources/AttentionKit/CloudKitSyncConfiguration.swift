import Foundation

public struct CloudKitSyncConfiguration: Sendable, Equatable {
    public let isEnabled: Bool
    public let containerIdentifier: String

    public init(
        isEnabled: Bool = true,
        containerIdentifier: String
    ) {
        self.isEnabled = isEnabled
        self.containerIdentifier = containerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isUsable: Bool {
        guard isEnabled else {
            return false
        }

        guard !containerIdentifier.isEmpty else {
            return false
        }

        return !containerIdentifier.contains("com.example")
    }
}
