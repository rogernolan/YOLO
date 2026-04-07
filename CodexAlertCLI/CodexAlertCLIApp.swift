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
            let store = FileAttentionAlertStore(directory: Self.defaultAlertsDirectory)
            try await store.save(alert)
            var cloudKitSync: CloudKitAttentionSync?
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
      CodexAlertCLI ask --title "Proceed?" --body "Should I continue with the risky fix?" [--sender Codex] [--task "Task name"] [--project "Project name"] [--urgency high] [--wait] [--timeout-seconds 1800]

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
