import SwiftUI

struct DashboardView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(16)
        .task {
            if store.snapshots.isEmpty {
                await store.refresh()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Takat")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Refresh usage")
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.snapshots.isEmpty && store.isRefreshing {
            ProgressView("Loading usage…")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if store.snapshots.isEmpty {
            emptyState
        } else {
            ForEach(ProviderID.allCases, id: \.self) { providerID in
                if let snapshot = store.snapshot(for: providerID) {
                    ProviderCardView(snapshot: snapshot)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No usage data yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

private struct ProviderCardView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(snapshot.provider.displayName, systemImage: snapshot.provider.symbolName)
                    .font(.headline)
                    .foregroundStyle(snapshot.provider.accentColor)
                Spacer()
                Text(snapshot.planName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            UsageBar(title: "Session", percent: snapshot.sessionPercent)
            UsageBar(title: "Weekly", percent: snapshot.weeklyPercent)

            if let resetDate = snapshot.resetDate {
                Text("Resets \(resetDate, format: .dateTime.month(.abbreviated).day())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            DailyUsageChart(usage: snapshot.dailyTokenUsage, color: snapshot.provider.accentColor)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct UsageBar: View {
    let title: String
    let percent: Double?

    private var percentText: String {
        percent.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(percent ?? 0, 100), total: 100)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(percent.map { "\(Int($0.rounded()))%" } ?? "No data")
    }
}

private struct DailyUsageChart: View {
    let usage: [DailyTokenUsage]
    let color: Color

    private var maxCount: Int {
        max(usage.map(\.tokenCount).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(usage, id: \.day) { entry in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: 14, height: barHeight(for: entry.tokenCount))
                    Text(entry.day, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 64, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily token usage")
    }

    private func barHeight(for count: Int) -> CGFloat {
        let ratio = CGFloat(count) / CGFloat(maxCount)
        return max(4, 44 * ratio)
    }
}
