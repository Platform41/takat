import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(ProviderID.allCases, id: \.self) { providerID in
                    LabeledContent {
                        statusText(for: providerID)
                    } label: {
                        Label {
                            Text(providerID.displayName)
                        } icon: {
                            ProviderMark(provider: providerID, size: 14)
                        }
                    }
                }
            }

            Section {
                Button("Refresh Now") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)

                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            } footer: {
                Text("Usage data is fixture-backed in this milestone. Live provider connections arrive in a later release.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .task {
            await store.loadPersistedSnapshots()
            if store.snapshots.isEmpty {
                await store.refresh()
            }
        }
    }

    @ViewBuilder
    private func statusText(for providerID: ProviderID) -> some View {
        if store.errors[providerID] != nil {
            Text("Unavailable")
                .foregroundStyle(.orange)
        } else if store.snapshot(for: providerID) != nil {
            Text("Connected")
                .foregroundStyle(.green)
        } else {
            Text("Not configured")
                .foregroundStyle(.secondary)
        }
    }
}
