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

            let configuration = CloudKitSyncConfiguration(
                containerIdentifier: ProcessInfo.processInfo.environment["CODEX_ALERT_CONTAINER"]
                    ?? "iCloud.net.hatbat.CodexAlert"
            )

            #if canImport(CloudKit)
            if configuration.isUsable {
                let sync = CloudKitAttentionSync(containerIdentifier: configuration.containerIdentifier)
                try await sync.upload(alert)
                print("Uploaded alert to CloudKit container \(configuration.containerIdentifier)")
            }
            #endif

            print("Saved alert \(alert.id.uuidString) to \(Self.defaultAlertsDirectory.path())")
            print("Title: \(alert.title)")
            print("Urgency: \(alert.urgency.rawValue)")
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
      CodexAlertCLI send --title "Need input" --body "Please review this blocker." [--sender Codex] [--urgency low|normal|high|critical]

    """
}
