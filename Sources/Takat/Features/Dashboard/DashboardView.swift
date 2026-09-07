import SwiftUI

func allZero(_ usage: [DailyTokenUsage]) -> Bool {
    usage.isEmpty || usage.allSatisfy { $0.tokenCount == 0 }
}

struct DashboardView: View {
    @Environment(UsageStore.self) private var store
    @AppStorage("takat.selectedProvider") private var storedProviderRaw = ""
    @State private var hoveredProvider: ProviderID?

    private var availableProviders: [ProviderID] {
        ProviderSwitcher.switcherProviders(snapshots: Set(store.snapshots.keys))
    }

    private var effectiveProvider: ProviderID {
        ProviderSwitcher.selectedProvider(stored: storedProviderRaw, available: availableProviders)
            ?? .claude
    }

    private var oldestLastUpdated: Date? {
        availableProviders.compactMap { store.lastUpdated(for: $0) }.min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(16)
        .task {
            await store.loadPersistedSnapshots()
            if store.needsRefreshOnOpen {
                await store.refresh()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RefreshPolicy.refreshInterval))
                guard !Task.isCancelled else { break }
                await store.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
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

            if let oldest = oldestLastUpdated {
                Text("Updated \(oldest, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(RefreshPolicy.isStale(oldest) ? .orange : .secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.snapshots.isEmpty && store.isRefreshing {
            ProgressView("Loading usage…")
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if store.snapshots.isEmpty {
            emptyState
        } else if availableProviders.count == 1, let single = availableProviders.first {
            providerCard(for: single)
        } else {
            VStack(spacing: 12) {
                providerSwitcher
                providerCard(for: effectiveProvider)
                    .animation(.easeInOut(duration: 0.15), value: effectiveProvider)
            }
        }
    }

    private var providerSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(availableProviders, id: \.self) { provider in
                let isSelected = effectiveProvider == provider
                Button {
                    storedProviderRaw = provider.rawValue
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: provider.symbolName)
                        Text(provider.displayName)
                        if store.errors[provider] != nil {
                            Circle()
                                .fill(.orange)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(segmentBackground(for: provider))
                .onHover { hovering in
                    hoveredProvider = hovering ? provider : nil
                }
                .accessibilityLabel("\(provider.displayName)\(store.errors[provider] != nil ? ", attention needed" : "")")
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .animation(.easeOut(duration: 0.1), value: hoveredProvider)
    }

    private func segmentBackground(for provider: ProviderID) -> Color {
        if effectiveProvider == provider {
            return provider.accentColor.opacity(0.18)
        } else if hoveredProvider == provider {
            return Color.primary.opacity(0.06)
        } else {
            return Color.clear
        }
    }

    @ViewBuilder
    private func providerCard(for providerID: ProviderID) -> some View {
        if let snapshot = store.snapshot(for: providerID) {
            ProviderCardView(
                snapshot: snapshot,
                lastUpdated: store.lastUpdated(for: providerID),
                hasError: store.errors[providerID] != nil
            )
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
    let lastUpdated: Date?
    let hasError: Bool

    private var isStale: Bool {
        guard let lastUpdated else { return false }
        return RefreshPolicy.isStale(lastUpdated)
    }

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

            freshnessRow

            if snapshot.sessionPercent == nil && snapshot.weeklyPercent == nil {
                Text("Session and weekly limits aren't reported by \(snapshot.provider.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                UsageBar(title: "Session", percent: snapshot.sessionPercent)
                    .tint(snapshot.provider.accentColor)
                UsageBar(title: "Weekly", percent: snapshot.weeklyPercent)
                    .tint(snapshot.provider.accentColor)
            }

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

    @ViewBuilder
    private var freshnessRow: some View {
        if let lastUpdated {
            HStack(spacing: 4) {
                if isStale {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(isStale ? .orange : .secondary)
                if hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Provider unavailable — showing last known data")
                }
            }
        }
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
        if allZero(usage) {
            Text("No usage in the last 7 days")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("No usage in the last 7 days")
        } else {
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
    }

    private func barHeight(for count: Int) -> CGFloat {
        let ratio = CGFloat(count) / CGFloat(maxCount)
        return max(4, 44 * ratio)
    }
}
