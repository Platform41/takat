import SwiftUI

@main
struct TakatApp: App {
    @State private var store: UsageStore

    init() {
        let providers: [any UsageProvider] = [
            ClaudeUsageProvider(),
            CodexUsageProvider(),
            GeminiUsageProvider(),
            DeepSeekUsageProvider()
        ]
        _store = State(initialValue: UsageStore(providers: providers))
    }

    var body: some Scene {
        MenuBarExtra("Takat", systemImage: "gauge.with.dots.needle.67percent") {
            DashboardView()
                .frame(width: 360)
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
