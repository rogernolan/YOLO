import Foundation

public struct AttentionDeviceRegistration: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let token: String
    public let platform: String
    public let bundleIdentifier: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        token: String,
        platform: String,
        bundleIdentifier: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) throws {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedID.isEmpty else {
            throw AttentionDeviceRegistrationError.emptyIdentifier
        }

        guard !normalizedToken.isEmpty else {
            throw AttentionDeviceRegistrationError.emptyToken
        }

        guard !normalizedPlatform.isEmpty else {
            throw AttentionDeviceRegistrationError.emptyPlatform
        }

        guard !normalizedBundleIdentifier.isEmpty else {
            throw AttentionDeviceRegistrationError.emptyBundleIdentifier
        }

        self.id = normalizedID
        self.token = normalizedToken
        self.platform = normalizedPlatform
        self.bundleIdentifier = normalizedBundleIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum AttentionDeviceRegistrationError: LocalizedError, Equatable {
    case emptyIdentifier
    case emptyToken
    case emptyPlatform
    case emptyBundleIdentifier

    public var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            "Device registration ID cannot be empty."
        case .emptyToken:
            "APNs device token cannot be empty."
        case .emptyPlatform:
            "Device platform cannot be empty."
        case .emptyBundleIdentifier:
            "Bundle identifier cannot be empty."
        }
    }
}
