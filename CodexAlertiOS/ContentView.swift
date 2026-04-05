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
                    List {
                        ForEach(model.alerts) { alert in
                            AlertRow(
                                alert: alert,
                                isUnread: model.isUnread(alert),
                                response: model.response(for: alert),
                                onRespond: { answer in
                                    Task {
                                        await model.submitResponse(answer, for: alert)
                                    }
                                }
                            )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task {
                                        await model.markAsRead(alert)
                                    }
                                }
                        }
                        .onDelete { offsets in
                            Task {
                                await model.deleteAlerts(at: offsets)
                            }
                        }
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
    let isUnread: Bool
    let response: AttentionResponse?
    let onRespond: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if isUnread {
                            Circle()
                                .fill(.blue)
                                .frame(width: 8, height: 8)
                        }

                        Text(alert.title)
                            .font(.headline)
                            .fontWeight(isUnread ? .semibold : .regular)
                    }

                    HStack(spacing: 8) {
                        Text(alert.type.rawValue.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(typeColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(typeColor)

                        if let projectName = alert.projectName {
                            Label(projectName, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Text(alert.urgency.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(urgencyColor)
            }

            Text(alert.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let taskName = alert.taskName {
                Label(taskName, systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let response {
                Label("Answered \(response.answer.capitalized)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else if let responseOptions = alert.responseOptions {
                HStack(spacing: 10) {
                    ForEach(responseOptions, id: \.self) { option in
                        Button(option.capitalized) {
                            onRespond(option)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(option == "yes" ? .green : .orange)
                        .controlSize(.small)
                    }
                }
            }

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

    private var typeColor: Color {
        switch alert.type {
        case .blocked:
            .red
        case .decision:
            .orange
        case .approval:
            .blue
        case .review:
            .green
        case .info:
            .secondary
        }
    }
}

#Preview {
    ContentView()
}
