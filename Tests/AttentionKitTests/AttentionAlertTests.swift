import Testing
@testable import AttentionKit
import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

@Test
func alertPayloadCapturesAttentionMetadata() throws {
    let alert = try AttentionAlert(
        title: "Need your attention",
        body: "Codex hit a blocker in the deployment pipeline.",
        sender: "Codex",
        urgency: .high
    )

    #expect(alert.title == "Need your attention")
    #expect(alert.body == "Codex hit a blocker in the deployment pipeline.")
    #expect(alert.sender == "Codex")
    #expect(alert.urgency == .high)
    #expect(alert.notificationTitle == "Codex needs your attention")
}

@Test
func fileStoreRoundTripsAlertsNewestFirst() async throws {
    let alertsDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = FileAttentionAlertStore(directory: alertsDirectory)

    let older = try AttentionAlert(
        title: "Earlier",
        body: "First blocker",
        sender: "Codex",
        urgency: .normal,
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let newer = try AttentionAlert(
        title: "Later",
        body: "Second blocker",
        sender: "Codex",
        urgency: .critical,
        createdAt: Date(timeIntervalSince1970: 2_000)
    )

    try await store.save(older)
    try await store.save(newer)

    let alerts = try await store.loadAll()
    #expect(alerts.map(\.title) == ["Later", "Earlier"])
}

@Test
func commandParserBuildsAnAlertFromFlags() throws {
    let command = try SendAlertCommand.parse([
        "send",
        "--title", "Build needs review",
        "--body", "Please check the TestFlight crash before I continue.",
        "--sender", "Codex",
        "--urgency", "critical",
    ])

    let alert = try command.makeAlert()
    #expect(alert.title == "Build needs review")
    #expect(alert.urgency == .critical)
    #expect(alert.sender == "Codex")
}

@Test
func cloudKitConfigurationRejectsPlaceholderIdentifiers() {
    #expect(CloudKitSyncConfiguration(containerIdentifier: "iCloud.com.example.CodexAlert").isUsable == false)
    #expect(CloudKitSyncConfiguration(containerIdentifier: "").isUsable == false)
    #expect(CloudKitSyncConfiguration(containerIdentifier: "iCloud.com.rog.CodexAlert").isUsable == true)
}

#if canImport(CloudKit)
@Test
func cloudKitBackgroundSubscriptionUsesSilentPushes() throws {
    let subscription = CloudKitAttentionSync.makeBackgroundSubscription()

    #expect(subscription.subscriptionID == CloudKitAttentionSync.backgroundSubscriptionID)
    #expect(subscription.recordType == CloudKitAttentionSync.feedRecordType)
    #expect(subscription.notificationInfo?.shouldSendContentAvailable == true)
}
#endif
