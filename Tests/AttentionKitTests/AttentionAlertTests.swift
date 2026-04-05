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
func askCommandBuildsAYesNoQuestionAndWaitsWhenRequested() throws {
    let command = try SendAlertCommand.parse([
        "ask",
        "--title", "Proceed with migration?",
        "--body", "I found a risky migration edge. Should I continue?",
        "--sender", "Codex",
        "--project", "Codex Alert",
        "--task", "Question flow",
        "--wait",
        "--timeout-seconds", "90",
    ])

    #expect(command.shouldWaitForResponse == true)
    #expect(command.timeoutSeconds == 90)

    let alert = try command.makeAlert()
    #expect(alert.responseOptions == ["yes", "no"])
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

@Test
func alertDecodesLegacyPayloadWithoutNewMetadata() throws {
    let data = Data(
        """
        {
          "body": "Please look at the latest build blocker.",
          "createdAt": "2026-04-04T14:14:17Z",
          "id": "52BDFE28-7FA5-4FEB-943D-3A5B833DBA9F",
          "sender": "Codex",
          "title": "Need review",
          "urgency": "high"
        }
        """.utf8
    )

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let alert = try decoder.decode(AttentionAlert.self, from: data)
    #expect(alert.type == .info)
    #expect(alert.taskName == nil)
    #expect(alert.projectName == nil)
}

@Test
func responseRecordRoundTripsAnswerPayload() throws {
    let response = AttentionResponse(
        alertID: UUID(uuidString: "52BDFE28-7FA5-4FEB-943D-3A5B833DBA9F")!,
        answer: "yes",
        responder: "Rog",
        respondedAt: Date(timeIntervalSince1970: 1_000)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try encoder.encode(response)
    let decoded = try decoder.decode(AttentionResponse.self, from: data)

    #expect(decoded == response)
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
