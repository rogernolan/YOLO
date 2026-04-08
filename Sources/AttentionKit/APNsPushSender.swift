import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct APNsPushSender: Sendable {
    private let configuration: APNsPushConfiguration
    private let session: URLSession

    public init(configuration: APNsPushConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func send(alert: AttentionAlert, to registrations: [AttentionDeviceRegistration]) async throws -> Int {
        guard configuration.isUsable else {
            throw APNsPushSenderError.invalidConfiguration
        }

        guard !registrations.isEmpty else {
            throw APNsPushSenderError.noRegistrations
        }

        let matchingRegistrations = registrations.filter { $0.bundleIdentifier == configuration.topic }
        guard !matchingRegistrations.isEmpty else {
            throw APNsPushSenderError.noMatchingRegistrations(topic: configuration.topic)
        }

        let jwt = try Self.makeJWT(configuration: configuration)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for registration in matchingRegistrations {
                group.addTask {
                    try await send(alert: alert, to: registration, jwt: jwt)
                }
            }

            try await group.waitForAll()
        }

        return matchingRegistrations.count
    }

    private func send(alert: AttentionAlert, to registration: AttentionDeviceRegistration, jwt: String) async throws {
        guard let url = URL(string: "https://\(configuration.host)/3/device/\(registration.token)") else {
            throw APNsPushSenderError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try Self.makePayload(alert: alert)
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue(configuration.topic, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APNsPushSenderError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APNsPushSenderError.deliveryFailed(statusCode: httpResponse.statusCode)
        }
    }

    private static func makePayload(alert: AttentionAlert) throws -> Data {
        let payload = APNsPayload(
            aps: APS(
                alert: APSAlert(
                    title: alert.notificationTitle,
                    subtitle: alert.title,
                    body: alert.body
                ),
                sound: "default",
                contentAvailable: 1
            ),
            alertID: alert.id.uuidString,
            projectName: alert.projectName,
            taskName: alert.taskName,
            type: alert.type.rawValue,
            responseOptions: alert.responseOptions
        )

        let encoder = JSONEncoder()
        return try encoder.encode(payload)
    }

    private static func makeJWT(configuration: APNsPushConfiguration) throws -> String {
        #if canImport(CryptoKit)
        let header = ["alg": "ES256", "kid": configuration.keyID]
        let claims = ["iss": configuration.teamID, "iat": String(Int(Date().timeIntervalSince1970))]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let claimsData = try JSONSerialization.data(withJSONObject: claims)
        let signingInput = "\(base64url(headerData)).\(base64url(claimsData))"

        let keyData = try Self.loadPrivateKeyData(from: configuration.keyPath)
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: String(decoding: keyData, as: UTF8.self))
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        let rawSignature = try Self.derToRaw(signature.derRepresentation)

        return "\(signingInput).\(base64url(rawSignature))"
        #else
        throw APNsPushSenderError.cryptoUnavailable
        #endif
    }

    private static func loadPrivateKeyData(from path: String) throws -> Data {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return try Data(contentsOf: URL(fileURLWithPath: expandedPath))
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func derToRaw(_ der: Data) throws -> Data {
        var bytes = Array(der)
        guard bytes.count > 8, bytes[0] == 0x30 else {
            throw APNsPushSenderError.invalidPrivateKey
        }

        bytes.removeFirst(2)
        guard bytes.first == 0x02 else {
            throw APNsPushSenderError.invalidPrivateKey
        }
        bytes.removeFirst()

        let rLength = Int(bytes.removeFirst())
        let r = Array(bytes.prefix(rLength))
        bytes.removeFirst(rLength)

        guard bytes.first == 0x02 else {
            throw APNsPushSenderError.invalidPrivateKey
        }
        bytes.removeFirst()

        let sLength = Int(bytes.removeFirst())
        let s = Array(bytes.prefix(sLength))

        return Data(paddedTo32Bytes(r) + paddedTo32Bytes(s))
    }

    private static func paddedTo32Bytes(_ bytes: [UInt8]) -> [UInt8] {
        let trimmed = bytes.drop { $0 == 0 }
        let value = Array(trimmed)
        if value.count >= 32 {
            return Array(value.suffix(32))
        }
        return Array(repeating: 0, count: 32 - value.count) + value
    }
}

private struct APNsPayload: Encodable {
    let aps: APS
    let alertID: String
    let projectName: String?
    let taskName: String?
    let type: String
    let responseOptions: [String]?
}

private struct APS: Encodable {
    let alert: APSAlert
    let sound: String
    let contentAvailable: Int

    enum CodingKeys: String, CodingKey {
        case alert
        case sound
        case contentAvailable = "content-available"
    }
}

private struct APSAlert: Encodable {
    let title: String
    let subtitle: String
    let body: String
}

public enum APNsPushSenderError: LocalizedError, Equatable {
    case invalidConfiguration
    case noRegistrations
    case noMatchingRegistrations(topic: String)
    case invalidEndpoint
    case invalidPrivateKey
    case invalidResponse
    case deliveryFailed(statusCode: Int)
    case cryptoUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "APNs configuration is incomplete."
        case .noRegistrations:
            "No APNs device registrations are available."
        case let .noMatchingRegistrations(topic):
            "No APNs device registrations match topic \(topic)."
        case .invalidEndpoint:
            "Could not create the APNs endpoint URL."
        case .invalidPrivateKey:
            "The APNs private key could not be parsed."
        case .invalidResponse:
            "APNs returned a non-HTTP response."
        case let .deliveryFailed(statusCode):
            "APNs rejected the notification with status \(statusCode)."
        case .cryptoUnavailable:
            "CryptoKit is required to sign APNs requests."
        }
    }
}
