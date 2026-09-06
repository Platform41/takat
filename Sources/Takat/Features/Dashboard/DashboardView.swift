import SwiftUI

struct DashboardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Takat")
                .font(.title2.weight(.semibold))

            Text("Usage dashboard coming next.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
