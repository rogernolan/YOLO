import Foundation

public struct LocalNotificationFallbackDecider: Sendable {
    public typealias Sleep = @Sendable (Duration) async throws -> Void
    public typealias RefreshDeliveredAlertIDs = @Sendable () async throws -> Set<UUID>

    private let delay: Duration
    private let sleep: Sleep

    public init(
        delay: Duration = .seconds(2),
        sleep: @escaping Sleep = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.delay = delay
        self.sleep = sleep
    }

    public func shouldNotifyLocally(
        for alertID: UUID,
        initiallyDeliveredAlertIDs: Set<UUID>,
        refreshDeliveredAlertIDs: RefreshDeliveredAlertIDs
    ) async throws -> Bool {
        guard !initiallyDeliveredAlertIDs.contains(alertID) else {
            return false
        }

        try await sleep(delay)

        let refreshedDeliveredAlertIDs = try await refreshDeliveredAlertIDs()
        return !refreshedDeliveredAlertIDs.contains(alertID)
    }
}
