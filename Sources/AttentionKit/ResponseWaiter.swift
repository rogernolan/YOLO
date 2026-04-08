import Foundation

public struct ResponseWaiter: Sendable {
    public typealias Now = @Sendable () -> Date
    public typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    public typealias FetchResponse = @Sendable () async throws -> AttentionResponse?
    public typealias SendFollowUp = @Sendable () async throws -> Void

    private let now: Now
    private let sleep: Sleep
    private let pollIntervalSeconds: TimeInterval

    public init(
        now: @escaping Now = Date.init,
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        pollIntervalSeconds: TimeInterval = 2
    ) {
        self.now = now
        self.sleep = sleep
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    public func waitForResponse(
        timeoutSeconds: Int,
        followUpAfterSeconds: Int? = nil,
        fetchResponse: @escaping FetchResponse,
        sendFollowUp: @escaping SendFollowUp = {}
    ) async throws -> AttentionResponse {
        let start = now()
        let deadline = start.addingTimeInterval(TimeInterval(timeoutSeconds))
        let followUpAt = followUpAfterSeconds.map { start.addingTimeInterval(TimeInterval($0)) }
        var didSendFollowUp = false

        while now() < deadline {
            if let response = try await fetchResponse() {
                return response
            }

            if let followUpAt, !didSendFollowUp, now() >= followUpAt {
                try await sendFollowUp()
                didSendFollowUp = true
            }

            let remaining = deadline.timeIntervalSince(now())
            guard remaining > 0 else {
                break
            }

            try await sleep(min(pollIntervalSeconds, remaining))
        }

        if let response = try await fetchResponse() {
            return response
        }

        throw ResponseWaiterError.timedOut
    }
}

public enum ResponseWaiterError: LocalizedError {
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .timedOut:
            "Timed out waiting for a response."
        }
    }
}
