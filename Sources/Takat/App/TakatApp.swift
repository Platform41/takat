import SwiftUI

@main
struct TakatApp: App {
    var body: some Scene {
        MenuBarExtra("Takat", systemImage: "gauge.with.dots.needle.67percent") {
            DashboardView()
                .frame(width: 360)
        }

        Settings {
            SettingsView()
        }
    }
}
