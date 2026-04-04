import Combine
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AlertCenterModel(
        store: FileAttentionAlertStore(
            directory: URL.documentsDirectory
                .appending(path: "Alerts", directoryHint: .isDirectory)
        )
    )

    var body: some View {
        NavigationStack {
            Group {
                if model.alerts.isEmpty && !model.isLoading {
                    ContentUnavailableView(
                        "No Alerts Yet",
                        systemImage: "bell.slash",
                        description: Text("Run the CLI with a CloudKit container configured, then pull to refresh.")
                    )
                } else {
                    List(model.alerts) { alert in
                        AlertRow(alert: alert)
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await model.refresh()
                    }
                }
            }
            .navigationTitle("Need Attention")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await model.refresh()
                        }
                    } label: {
                        if model.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh alerts")
                }
            }
        }
        .task {
            await model.requestNotifications()
            await model.loadCachedAlerts()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await model.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .attentionAlertsDidChange)) { _ in
            Task {
                await model.loadCachedAlerts()
            }
        }
        .alert("Sync Error", isPresented: syncErrorBinding, actions: {
            Button("OK") {
                model.errorMessage = nil
            }
        }, message: {
            Text(model.errorMessage ?? "Unknown error")
        })
    }

    private var syncErrorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            }
        )
    }
}

private struct AlertRow: View {
    let alert: AttentionAlert

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(alert.title)
                    .font(.headline)
                Spacer()
                Text(alert.urgency.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(urgencyColor)
            }

            Text(alert.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Label(alert.sender, systemImage: "person.wave.2")
                Spacer()
                Text(alert.createdAt, style: .relative)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var urgencyColor: Color {
        switch alert.urgency {
        case .low:
            .blue
        case .normal:
            .secondary
        case .high:
            .orange
        case .critical:
            .red
        }
    }
}

#Preview {
    ContentView()
}
