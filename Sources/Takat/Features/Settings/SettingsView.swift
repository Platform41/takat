import SwiftUI

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @State private var draftKey = ""
    @State private var hasKey = KeychainStore.get("deepseek") != nil

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
                LabeledContent("Status") {
                    deepSeekStatusText
                }

                SecureField("API key", text: $draftKey)

                HStack {
                    Button("Save") {
                        KeychainStore.set("deepseek", draftKey)
                        draftKey = ""
                        hasKey = KeychainStore.get("deepseek") != nil
                        Task { await store.refresh() }
                    }
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if hasKey {
                        Button("Remove", role: .destructive) {
                            KeychainStore.delete("deepseek")
                            draftKey = ""
                            hasKey = false
                            Task { await store.refresh() }
                        }
                    }
                }
            } header: {
                Text("DeepSeek")
            } footer: {
                Text("Your key is stored in the macOS Keychain and used only to read your balance from api.deepseek.com.")
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

            Section {
                Toggle("Open Takat at Login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Requires running Takat from /Applications. An unsigned build may need approval in System Settings → General → Login Items.")
                    Text(appVersionString)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .task {
            hasKey = KeychainStore.get("deepseek") != nil
            await store.loadPersistedSnapshots()
            if store.snapshots.isEmpty {
                await store.refresh()
            }
        }
    }

    @ViewBuilder
    private var deepSeekStatusText: some View {
        if !hasKey {
            Text("Not connected")
                .foregroundStyle(.secondary)
        } else if store.errors[.deepseek] == .unauthorized {
            Text("Invalid key")
                .foregroundStyle(.orange)
        } else if store.errors[.deepseek] == .unavailable {
            Text("Can't reach DeepSeek")
                .foregroundStyle(.orange)
        } else if store.snapshot(for: .deepseek) != nil {
            Text("Connected")
                .foregroundStyle(.green)
        } else if store.errors[.deepseek] != nil {
            Text("Unavailable")
                .foregroundStyle(.orange)
        } else {
            Text("Not connected")
                .foregroundStyle(.secondary)
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Takat \(version) (build \(build))"
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
