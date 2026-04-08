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
func askCommandBuildsCustomThreeChoiceQuestion() throws {
    let command = try SendAlertCommand.parse([
        "ask",
        "--title", "What should I do?",
        "--body", "Choose the next step.",
        "--option", "ship",
        "--option", "hold",
        "--option", "investigate",
    ])

    let alert = try command.makeAlert()
    #expect(alert.responseOptions == ["ship", "hold", "investigate"])
    #expect(alert.type == .decision)
}

@Test
func askCommandRejectsMoreThanThreeOptions() throws {
    #expect(throws: SendAlertCommandError.self) {
        try SendAlertCommand.parse([
            "ask",
            "--title", "Too many",
            "--body", "This should fail.",
            "--option", "one",
            "--option", "two",
            "--option", "three",
            "--option", "four",
        ])
    }
}

@Test
func attentionAlertRejectsSingleResponseOption() {
    #expect(throws: AttentionAlertError.self) {
        _ = try AttentionAlert(
            title: "Need input",
            body: "Pick one.",
            sender: "Codex",
            responseOptions: ["only"]
        )
    }
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

@Test
func deviceRegistrationNormalizesTokenAndBundleMetadata() throws {
    let registration = try AttentionDeviceRegistration(
        id: " install-1 ",
        token: " ABCDEF1234 ",
        platform: " iOS ",
        bundleIdentifier: " net.hatbat.CodexAlert "
    )

    #expect(registration.id == "install-1")
    #expect(registration.token == "abcdef1234")
    #expect(registration.platform == "iOS")
    #expect(registration.bundleIdentifier == "net.hatbat.CodexAlert")
}

@Test
func apnsConfigurationLoadsFromEnvironment() {
    let configuration = APNsPushConfiguration.fromEnvironment(
        [
            "CODEX_ALERT_APNS_KEY_ID": "ABC123XYZ",
            "CODEX_ALERT_APNS_TEAM_ID": "TEAM123456",
            "CODEX_ALERT_APNS_KEY_PATH": "/tmp/AuthKey_TEST.p8",
            "CODEX_ALERT_APNS_USE_SANDBOX": "true",
        ],
        defaultTopic: "net.hatbat.CodexAlert"
    )

    #expect(configuration.keyID == "ABC123XYZ")
    #expect(configuration.teamID == "TEAM123456")
    #expect(configuration.keyPath == "/tmp/AuthKey_TEST.p8")
    #expect(configuration.topic == "net.hatbat.CodexAlert")
    #expect(configuration.useSandbox == true)
    #expect(configuration.host == "api.sandbox.push.apple.com")
}

@Test
func localFallbackSkipsNotificationWhenAlreadyMarkedRemoteDelivered() async throws {
    let alertID = UUID()
    let decider = LocalNotificationFallbackDecider(
        delay: .seconds(2),
        sleep: { _ in }
    )

    let shouldNotify = try await decider.shouldNotifyLocally(
        for: alertID,
        initiallyDeliveredAlertIDs: [alertID],
        refreshDeliveredAlertIDs: { [] }
    )

    #expect(shouldNotify == false)
}

@Test
func localFallbackSkipsNotificationWhenRemoteDeliveryArrivesDuringGracePeriod() async throws {
    let alertID = UUID()
    let decider = LocalNotificationFallbackDecider(
        delay: .seconds(2),
        sleep: { _ in }
    )

    let shouldNotify = try await decider.shouldNotifyLocally(
        for: alertID,
        initiallyDeliveredAlertIDs: [],
        refreshDeliveredAlertIDs: { [alertID] }
    )

    #expect(shouldNotify == false)
}

@Test
func localFallbackNotifiesWhenRemoteDeliveryNeverArrives() async throws {
    let alertID = UUID()
    let decider = LocalNotificationFallbackDecider(
        delay: .seconds(2),
        sleep: { _ in }
    )

    let shouldNotify = try await decider.shouldNotifyLocally(
        for: alertID,
        initiallyDeliveredAlertIDs: [],
        refreshDeliveredAlertIDs: { [] }
    )

    #expect(shouldNotify == true)
}

#if canImport(CloudKit)
@Test
func cloudKitBackgroundSubscriptionUsesSilentPushes() throws {
    let subscription = CloudKitAttentionSync.makeBackgroundSubscription()

    #expect(subscription.subscriptionID == CloudKitAttentionSync.backgroundSubscriptionID)
    #expect(subscription.recordType == CloudKitAttentionSync.feedRecordType)
    #expect(subscription.notificationInfo?.shouldSendContentAvailable == true)
}

@Test
func cloudKitDeviceRegistrationRecordNameUsesStablePrefix() {
    #expect(
        CloudKitAttentionSync.deviceRegistrationRecordName(for: "install-1")
            == "device-install-1"
    )
}

@Test
func cloudKitFeedRecordNamesRemoveDeletedAlertAndPreserveOrder() {
    let updated = CloudKitAttentionSync.updatedRecordNames(
        from: ["c", "b", "a"],
        removing: "b",
        limit: 50
    )

    #expect(updated == ["c", "a"])
}
#endif
