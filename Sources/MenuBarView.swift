// MenuBarView.swift
// L'interface qui s'affiche quand on clique sur l'icône dans la menu bar

import SwiftUI

// MARK: - Vue principale

struct MenuBarView: View {
    @ObservedObject var manager: UsageManager
    @State private var copiedFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if manager.updateAvailable {
                updateBanner
            }

            Divider()
                .opacity(0.5)

            Group {
                if !manager.isAuthenticated || manager.showSettings {
                    settingsView
                } else if manager.showStats {
                    statsView
                } else if manager.isLoading && manager.lastRefresh == nil {
                    loadingView
                } else if let error = manager.errorMessage {
                    errorView(error)
                } else if !manager.quotas.isEmpty {
                    if manager.compactMode {
                        compactUsageView
                    } else {
                        usageView
                    }
                } else {
                    emptyView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .opacity(0.5)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: manager.compactMode && !manager.showSettings && !manager.showStats ? 260 : 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.58, green: 0.29, blue: 0.98),
                                Color(red: 0.35, green: 0.22, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 26, height: 26)
                    .shadow(color: .purple.opacity(0.3), radius: 4, y: 2)
                Text("C")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Claude God")
                    .font(.system(size: 14, weight: .bold))
                if !manager.subscriptionType.isEmpty {
                    Text(manager.subscriptionType.capitalized)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.purple)
                }
            }

            Spacer()

            if let lastRefresh = manager.lastRefresh, !manager.showSettings && !manager.showStats {
                HStack(spacing: 3) {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                    Text(lastRefresh.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            // Stats button
            if manager.isAuthenticated && !manager.showSettings {
                Button(action: { manager.showStats.toggle() }) {
                    Image(systemName: manager.showStats ? "chart.bar.fill" : "chart.bar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(manager.showStats ? .purple : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(manager.showStats ? 0.08 : 0.04))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                manager.showSettings.toggle()
                if manager.showSettings { manager.showStats = false }
            }) {
                Image(systemName: manager.showSettings ? "xmark" : "gearshape.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(manager.showSettings ? 0.08 : 0.04))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Update banner

    private var updateBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("v\(manager.latestVersion) available")
                    .font(.system(size: 11, weight: .semibold))
                Text("v\(UsageManager.currentVersion) installed")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Update") {
                manager.installUpdate()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.08), Color.purple.opacity(0.03)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - Settings

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection(title: "Authentication", icon: "person.badge.key.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    if manager.isAuthenticated {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("via \(manager.credentialSource.rawValue)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if !manager.subscriptionType.isEmpty {
                                Text(manager.subscriptionType.capitalized)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.purple.opacity(0.12))
                                    )
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not connected")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Run `claude login` in Terminal")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button(action: {
                            manager.loadCredentials()
                            if manager.isAuthenticated {
                                manager.showSettings = false
                                manager.refresh()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Retry")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                    }
                }
            }

            SettingsSection(title: "Auto-refresh", icon: "arrow.triangle.2.circlepath") {
                Picker("Interval", selection: $manager.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingsSection(title: "Notifications", icon: "bell.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Alert when usage is high", isOn: $manager.notificationsEnabled)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.purple)

                    if manager.notificationsEnabled {
                        HStack(spacing: 8) {
                            Text("Threshold")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Slider(value: $manager.notificationThreshold, in: 5...50, step: 5)
                                .controlSize(.small)
                                .tint(.purple)
                            Text("\(Int(manager.notificationThreshold))%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }

            SettingsSection(title: "Display", icon: "rectangle.on.rectangle") {
                Toggle("Compact mode", isOn: $manager.compactMode)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.purple)
            }

            SettingsSection(title: "System", icon: "laptopcomputer") {
                Toggle("Launch at login", isOn: $manager.launchAtLogin)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.purple)
            }
        }
    }

    // MARK: - Usage (full)

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(manager.quotas) { quota in
                QuotaBar(quota: quota)
            }

            // Reset countdown card
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(.purple.opacity(0.8))
                Text("Next reset")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))

                if manager.refreshInterval != .off {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.purple.opacity(0.6))
                        .help("Auto-refresh: \(manager.refreshInterval.label)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.03))
            )
        }
    }

    // MARK: - Usage (compact)

    private var compactUsageView: some View {
        VStack(spacing: 6) {
            ForEach(manager.quotas) { quota in
                HStack(spacing: 8) {
                    Image(systemName: quota.icon)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Text(quota.label)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(quota.utilization))%")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(quota.level.color)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Stats view

    private var statsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Cost summary cards
            HStack(spacing: 8) {
                CostCard(label: "Today", cost: manager.todayStats.totalCost, messages: manager.todayStats.totalMessages)
                CostCard(label: "7 days", cost: manager.weekStats.totalCost, messages: manager.weekStats.totalMessages)
                CostCard(label: "30 days", cost: manager.monthStats.totalCost, messages: manager.monthStats.totalMessages)
            }

            // Sparkline chart
            if manager.monthStats.daily.count >= 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("USAGE TREND (7D)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)

                    SparklineView(
                        data: Array(manager.monthStats.daily.prefix(7).reversed().map(\.cost))
                    )
                    .frame(height: 40)
                }
            }

            // Model breakdown
            if !manager.monthStats.byModel.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MODELS (30D)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)

                    ForEach(manager.monthStats.byModel) { model in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorForModel(model.model))
                                .frame(width: 6, height: 6)
                            Text(model.shortName)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(formatTokens(model.tokens.totalTokens))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(formatCost(model.cost))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                    }
                }
            }

            // Daily history
            if !manager.monthStats.daily.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAILY HISTORY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.8)

                    ForEach(manager.monthStats.daily.prefix(7)) { day in
                        HStack(spacing: 8) {
                            Text(day.dateLabel)
                                .font(.system(size: 11))
                                .frame(width: 70, alignment: .leading)
                            DailyBar(cost: day.cost, maxCost: maxDailyCost)
                            Text(formatCost(day.cost))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .frame(width: 55, alignment: .trailing)
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    if manager.copyStatsToClipboard() {
                        copiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedFeedback = false
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(copiedFeedback ? "Copied!" : "Copy")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(copiedFeedback ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(copiedFeedback ? .green : .secondary)

                Button(action: { manager.exportCSV() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Export CSV")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()
            }
        }
    }

    private var maxDailyCost: Double {
        manager.monthStats.daily.prefix(7).map(\.cost).max() ?? 1
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.purple)
            Text("Fetching usage...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Text("Check settings for details")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.06))
        )
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 20))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Click Refresh to load data")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: { manager.refresh() }) {
                HStack(spacing: 5) {
                    if manager.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text("Refresh")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(!manager.isAuthenticated || manager.isLoading
                              ? Color.clear
                              : Color.purple.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .foregroundColor(manager.isLoading ? .secondary : .purple)
            .disabled(!manager.isAuthenticated || manager.isLoading)

            Spacer()

            Text("v\(UsageManager.currentVersion)")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.4))

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func formatCost(_ cost: Double) -> String {
        if cost >= 1 { return String(format: "$%.2f", cost) }
        if cost >= 0.01 { return String(format: "$%.2f", cost) }
        return String(format: "$%.3f", cost)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func colorForModel(_ model: String) -> Color {
        if model.contains("opus") { return .purple }
        if model.contains("sonnet") { return .blue }
        if model.contains("haiku") { return .green }
        return .gray
    }
}

// MARK: - Settings section wrapper

struct SettingsSection<Content: View>: View {
    let title: String
    var icon: String = ""
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.purple.opacity(0.7))
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.8)
            }
            content
        }
    }
}

// MARK: - Quota bar component

struct QuotaBar: View {
    let quota: UsageQuota

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Image(systemName: quota.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(quota.label)
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                Text("\(Int(quota.utilization))%")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(quota.level.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [quota.level.color.opacity(0.7), quota.level.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(quota.utilization / 100)))
                        .shadow(color: quota.level.color.opacity(0.3), radius: 3, y: 1)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: quota.utilization)
                }
            }
            .frame(height: 8)

            if let resetsAt = quota.resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                Text("Resets \(resetsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Cost card component

struct CostCard: View {
    let label: String
    let cost: Double
    let messages: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(cost >= 1 ? String(format: "$%.2f", cost) : String(format: "$%.3f", cost))
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(.primary)
            Text("\(messages) msgs")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

// MARK: - Daily bar component

struct DailyBar: View {
    let cost: Double
    let maxCost: Double

    private var fraction: Double {
        guard maxCost > 0 else { return 0 }
        return cost / maxCost
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.6), .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Sparkline component

struct SparklineView: View {
    let data: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxVal = data.max() ?? 1
            let minVal = data.min() ?? 0
            let range = max(maxVal - minVal, 0.001)
            let stepX = geo.size.width / CGFloat(max(data.count - 1, 1))
            let points: [CGPoint] = data.enumerated().map { i, val in
                let x = CGFloat(i) * stepX
                let y = geo.size.height - (CGFloat((val - minVal) / range) * (geo.size.height - 4)) - 2
                return CGPoint(x: x, y: y)
            }

            ZStack {
                // Fill area
                if points.count >= 2 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        path.addLine(to: points[0])
                        for i in 1..<points.count {
                            path.addLine(to: points[i])
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            path.addLine(to: points[i])
                        }
                    }
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                // Dots
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 4, height: 4)
                        .position(point)
                }
            }
        }
    }
}
