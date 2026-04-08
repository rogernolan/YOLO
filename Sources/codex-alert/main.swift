import AttentionKit
import Foundation

@main
struct CodexAlertCLI {
    static func main() async {
        do {
            let command = try SendAlertCommand.parse(Array(CommandLine.arguments.dropFirst()))
            let alert = try command.makeAlert()
            let store = FileAttentionAlertStore(directory: Self.defaultAlertsDirectory)
            try await store.save(alert)
            var cloudKitSync: CloudKitAttentionSync?
            let apnsConfiguration = APNsPushConfiguration.fromEnvironment(
                ProcessInfo.processInfo.environment,
                defaultTopic: "net.hatbat.CodexAlert"
            )

            #if canImport(CloudKit)
            if let containerIdentifier = ProcessInfo.processInfo.environment["CODEX_ALERT_CONTAINER"],
               CloudKitSyncConfiguration(containerIdentifier: containerIdentifier).isUsable {
                let sync = CloudKitAttentionSync(containerIdentifier: containerIdentifier)
                try await sync.upload(alert)
                cloudKitSync = sync
                print("Uploaded alert to CloudKit container \(containerIdentifier)")

                if apnsConfiguration.isUsable {
                    let registrations = try await sync.fetchDeviceRegistrations()
                    if registrations.isEmpty {
                        print("No registered APNs devices found; skipping direct push.")
                    } else {
                        let sender = APNsPushSender(configuration: apnsConfiguration)
                        try await sender.send(alert: alert, to: registrations)
                        print("Sent APNs push to \(registrations.count) registered device(s)")
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

            if command.shouldWaitForResponse {
                guard let cloudKitSync else {
                    throw WaitForResponseError.cloudKitUnavailable
                }

                print("Waiting up to \(command.timeoutSeconds)s for a response...")
                let response = try await waitForResponse(
                    alertID: alert.id,
                    timeoutSeconds: command.timeoutSeconds,
                    sync: cloudKitSync
                )
                print("Response: \(response.answer)")
                print("Responder: \(response.responder)")
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            fputs(Self.usage, stderr)
            exit(1)
        }
    }

    private static let defaultAlertsDirectory = URL.applicationSupportDirectory
        .appending(path: "CodexAlert", directoryHint: .isDirectory)
        .appending(path: "Alerts", directoryHint: .isDirectory)

    private static let usage = """
    Usage:
      codex-alert send --title "Need input" --body "Please review this blocker." [--sender Codex] [--urgency low|normal|high|critical] [--task "Task name"] [--project "Project name"] [--type blocked|decision|approval|review|info]
      codex-alert ask --title "Proceed?" --body "Should I continue with the risky fix?" [--sender Codex] [--task "Task name"] [--project "Project name"] [--urgency high] [--option "yes"] [--option "no"] [--option "later"] [--wait] [--timeout-seconds 1800]

    """

    private static func waitForResponse(
        alertID: UUID,
        timeoutSeconds: Int,
        sync: CloudKitAttentionSync
    ) async throws -> AttentionResponse {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

        while Date() < deadline {
            if let response = try await sync.fetchResponse(for: alertID) {
                return response
            }

            try await Task.sleep(for: .seconds(2))
        }

        throw WaitForResponseError.timedOut
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
