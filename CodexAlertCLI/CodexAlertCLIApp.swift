import AppKit
import SwiftUI

@main
struct CodexAlertCLIApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.prohibited)

        Task {
            await Self.runAndExit()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }

    private static func runAndExit() async {
        do {
            let command = try SendAlertCommand.parse(Array(CommandLine.arguments.dropFirst()))
            let alert = try command.makeAlert()
            let apnsConfiguration = APNsPushConfiguration.fromEnvironment(
                ProcessInfo.processInfo.environment.reduce(into: [String: String]()) { result, item in
                    result[item.key] = item.value
                },
                defaultTopic: "net.hatbat.CodexAlert"
            )

            let configuration = CloudKitSyncConfiguration(
                containerIdentifier: ProcessInfo.processInfo.environment["CODEX_ALERT_CONTAINER"]
                    ?? "iCloud.net.hatbat.CodexAlert"
            )
            let cloudKitSync = try await deliver(
                alert: alert,
                apnsConfiguration: apnsConfiguration,
                configuration: configuration
            )

            if command.shouldWaitForResponse {
                guard let cloudKitSync else {
                    throw WaitForResponseError.cloudKitUnavailable
                }

                print("Waiting up to \(command.timeoutSeconds)s for a response...")
                let response = try await ResponseWaiter().waitForResponse(
                    timeoutSeconds: command.timeoutSeconds,
                    followUpAfterSeconds: command.followUpAfterSeconds,
                    fetchResponse: {
                        try await cloudKitSync.fetchResponse(for: alert.id)
                    },
                    sendFollowUp: {
                        guard let followUpAlert = try command.makeFollowUpAlert() else {
                            return
                        }

                        _ = try await deliver(
                            alert: followUpAlert,
                            apnsConfiguration: apnsConfiguration,
                            configuration: configuration
                        )
                    }
                )
                print("Response: \(response.answer)")
                print("Responder: \(response.responder)")
            }
            terminate(with: EXIT_SUCCESS)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            fputs(Self.usage, stderr)
            terminate(with: EXIT_FAILURE)
        }
    }

    @MainActor
    private static func terminate(with code: Int32) {
        NSApp.reply(toApplicationShouldTerminate: true)
        exit(code)
    }

    private static let defaultAlertsDirectory = URL.applicationSupportDirectory
        .appending(path: "CodexAlert", directoryHint: .isDirectory)
        .appending(path: "Alerts", directoryHint: .isDirectory)

    private static let usage = """
    Usage:
      CodexAlertCLI send --title "Need input" --body "Please review this blocker." [--sender Codex] [--urgency low|normal|high|critical] [--task "Task name"] [--project "Project name"] [--type blocked|decision|approval|review|info]
      CodexAlertCLI ask --title "Proceed?" --body "Should I continue with the risky fix?" [--sender Codex] [--task "Task name"] [--project "Project name"] [--urgency high] [--option "yes"] [--option "no"] [--option "later"] [--wait] [--timeout-seconds 1800] [--follow-up-after-seconds 300] [--follow-up-title "Question still waiting"] [--follow-up-body "The earlier question is still unanswered."]

    """

    private static func deliver(
        alert: AttentionAlert,
        apnsConfiguration: APNsPushConfiguration,
        configuration: CloudKitSyncConfiguration
    ) async throws -> CloudKitAttentionSync? {
        let store = FileAttentionAlertStore(directory: Self.defaultAlertsDirectory)
        try await store.save(alert)
        var cloudKitSync: CloudKitAttentionSync?

        #if canImport(CloudKit)
        if configuration.isUsable {
            let sync = CloudKitAttentionSync(containerIdentifier: configuration.containerIdentifier)
            try await sync.upload(alert)
            cloudKitSync = sync
            print("Uploaded alert to CloudKit container \(configuration.containerIdentifier)")

            if apnsConfiguration.isUsable {
                let registrations = try await sync.fetchDeviceRegistrations()
                    if registrations.isEmpty {
                        print("No registered APNs devices found; skipping direct push.")
                    } else {
                        let sender = APNsPushSender(configuration: apnsConfiguration)
                        let deliveredCount = try await sender.send(alert: alert, to: registrations)
                        print("Sent APNs push to \(deliveredCount) registered device(s)")
                    }
                } else {
                    print("APNs configuration not present; skipping direct push.")
                }
        }
        #endif

        print("Saved alert \(alert.id.uuidString) to \(Self.defaultAlertsDirectory.path())")
        print("Title: \(alert.title)")
        if let projectName = alert.projectName {
            print("Project: \(projectName)")
        }
        if let taskName = alert.taskName {
            print("Task: \(taskName)")
        }
        print("Type: \(alert.type.rawValue)")
        if let responseOptions = alert.responseOptions {
            print("Response options: \(responseOptions.joined(separator: ", "))")
        }
        print("Urgency: \(alert.urgency.rawValue)")

        return cloudKitSync
    }
}

private enum WaitForResponseError: LocalizedError {
    case cloudKitUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cloudKitUnavailable:
            "Waiting for a response requires a usable CODEX_ALERT_CONTAINER value."
        case .timedOut:
            "Timed out waiting for a response."
        }
    }
}
