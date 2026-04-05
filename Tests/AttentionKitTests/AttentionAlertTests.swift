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
        urgency: .high,
        taskName: "Fix deployment pipeline",
        projectName: "Codex Alert",
        type: .blocked
    )

    #expect(alert.title == "Need your attention")
    #expect(alert.body == "Codex hit a blocker in the deployment pipeline.")
    #expect(alert.sender == "Codex")
    #expect(alert.urgency == .high)
    #expect(alert.taskName == "Fix deployment pipeline")
    #expect(alert.projectName == "Codex Alert")
    #expect(alert.type == .blocked)
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
        "--task", "TestFlight crash",
        "--project", "Codex Alert",
        "--type", "decision",
    ])

    let alert = try command.makeAlert()
    #expect(alert.title == "Build needs review")
    #expect(alert.urgency == .critical)
    #expect(alert.sender == "Codex")
    #expect(alert.taskName == "TestFlight crash")
    #expect(alert.projectName == "Codex Alert")
    #expect(alert.type == .decision)
}

@Test
func cloudKitConfigurationRejectsPlaceholderIdentifiers() {
    #expect(CloudKitSyncConfiguration(containerIdentifier: "iCloud.com.example.CodexAlert").isUsable == false)
    #expect(CloudKitSyncConfiguration(containerIdentifier: "").isUsable == false)
    #expect(CloudKitSyncConfiguration(containerIdentifier: "iCloud.com.rog.CodexAlert").isUsable == true)
}

@Test
func fileStoreDeletesAlertsByIdentifier() async throws {
    let alertsDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = FileAttentionAlertStore(directory: alertsDirectory)

    let alert = try AttentionAlert(
        title: "Delete me",
        body: "This should disappear from the store.",
        sender: "Codex"
    )

    try await store.save(alert)
    try await store.delete(ids: [alert.id])

    let alerts = try await store.loadAll()
    #expect(alerts.isEmpty)
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
