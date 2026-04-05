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

            #if canImport(CloudKit)
            if let containerIdentifier = ProcessInfo.processInfo.environment["CODEX_ALERT_CONTAINER"],
               CloudKitSyncConfiguration(containerIdentifier: containerIdentifier).isUsable {
                let sync = CloudKitAttentionSync(containerIdentifier: containerIdentifier)
                try await sync.upload(alert)
                print("Uploaded alert to CloudKit container \(containerIdentifier)")
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
            print("Urgency: \(alert.urgency.rawValue)")
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

    """
}
