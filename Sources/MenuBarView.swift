// MenuBarView.swift
// L'interface qui s'affiche quand on clique sur l'icône dans la menu bar

import SwiftUI

// MARK: - Vue principale

struct MenuBarView: View {
    @ObservedObject var manager: UsageManager
    @State private var copiedFeedback = false
    @State private var hoveredQuotaId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if manager.updateAvailable {
                updateBanner
            }

            // Navigation tabs
            if manager.isAuthenticated && !manager.showSettings {
                navTabs
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider()
                .opacity(0.3)

            ScrollView(.vertical, showsIndicators: false) {
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
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 420)

            Divider()
                .opacity(0.3)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: manager.compactMode && !manager.showSettings && !manager.showStats ? 280 : 360)
        .animation(.easeInOut(duration: 0.2), value: manager.showStats)
        .animation(.easeInOut(duration: 0.2), value: manager.showSettings)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.25, blue: 1.0),
                                Color(red: 0.40, green: 0.18, blue: 0.95)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(color: Color(red: 0.55, green: 0.25, blue: 1.0).opacity(0.4), radius: 6, y: 3)
                Text("C")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Claude God")
                    .font(.system(size: 14, weight: .bold))
                HStack(spacing: 4) {
                    if !manager.subscriptionType.isEmpty {
                        Text(manager.subscriptionType.capitalized)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.purple, .purple.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                    }
                    if let lastRefresh = manager.lastRefresh, !manager.showSettings && !manager.showStats {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(.green)
                                .frame(width: 4, height: 4)
                            Text(lastRefresh.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            // Settings button
            IconButton(
                icon: manager.showSettings ? "xmark" : "gearshape.fill",
                isActive: manager.showSettings
            ) {
                withAnimation(.spring(response: 0.3)) {
                    manager.showSettings.toggle()
                    if manager.showSettings { manager.showStats = false }
                }
            }
        }
    }

    // MARK: - Navigation tabs

    private var navTabs: some View {
        HStack(spacing: 2) {
            TabPill(label: "Usage", icon: "gauge.medium", isActive: !manager.showStats) {
                withAnimation(.spring(response: 0.3)) { manager.showStats = false }
            }
            TabPill(label: "Stats", icon: "chart.bar.fill", isActive: manager.showStats) {
                withAnimation(.spring(response: 0.3)) { manager.showStats = true }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Update banner

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom)
                )
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 1) {
                Text("v\(manager.latestVersion) available")
                    .font(.system(size: 11, weight: .semibold))
                Text("v\(UsageManager.currentVersion) installed")
                    .font(.system(size: 9))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Settings

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                SettingsSection(title: "Authentication", icon: "person.badge.key.fill") {
                    if manager.isAuthenticated {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("via \(manager.credentialSource.rawValue)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.system(size: 16))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Not connected")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Run `claude login` in Terminal")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            PillButton(label: "Retry", icon: "arrow.clockwise") {
                                manager.loadCredentials()
                                if manager.isAuthenticated {
                                    manager.showSettings = false
                                    manager.refresh()
                                }
                            }
                        }
                    }
                }
            }

            GlassCard {
                SettingsSection(title: "Auto-refresh", icon: "arrow.triangle.2.circlepath") {
                    Picker("Interval", selection: $manager.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            GlassCard {
                SettingsSection(title: "Notifications", icon: "bell.fill") {
                    VStack(alignment: .leading, spacing: 10) {
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
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.purple)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            GlassCard {
                SettingsSection(title: "Display", icon: "rectangle.on.rectangle") {
                    Toggle("Compact mode", isOn: $manager.compactMode)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.purple)
                }
            }

            GlassCard {
                SettingsSection(title: "System", icon: "laptopcomputer") {
                    Toggle("Launch at login", isOn: $manager.launchAtLogin)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(.purple)
                }
            }
        }
    }

    // MARK: - Usage (full)

    private var usageView: some View {
        VStack(spacing: 10) {
            // Circular gauges row
            HStack(spacing: 0) {
                ForEach(manager.quotas) { quota in
                    CircularGauge(quota: quota, isHovered: hoveredQuotaId == quota.id)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredQuotaId = hovering ? quota.id : nil
                            }
                        }
                    if quota.id != manager.quotas.last?.id {
                        Spacer(minLength: 0)
                    }
                }
            }

            // Reset countdown
            GlassCard {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Next reset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(manager.timeUntilReset)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        )

                    if manager.refreshInterval != .off {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.purple.opacity(0.5))
                            .help("Auto-refresh: \(manager.refreshInterval.label)")
                    }
                }
            }
        }
    }

    // MARK: - Usage (compact)

    private var compactUsageView: some View {
        VStack(spacing: 6) {
            ForEach(manager.quotas) { quota in
                HStack(spacing: 8) {
                    Image(systemName: quota.icon)
                        .font(.system(size: 9))
                        .foregroundColor(quota.level.color.opacity(0.8))
                        .frame(width: 14)
                    Text(quota.label)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()

                    // Mini inline bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 40, height: 4)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(quota.level.color)
                                .frame(width: 40 * CGFloat(min(quota.utilization, 100) / 100))
                        }

                    Text("\(Int(quota.utilization))%")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(quota.level.color)
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }

            Divider().opacity(0.2).padding(.vertical, 2)

            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("Reset")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Stats view

    private var statsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cost summary cards
            HStack(spacing: 8) {
                StatCard(label: "Today", cost: manager.todayStats.totalCost, messages: manager.todayStats.totalMessages, icon: "sun.max.fill", accent: .orange)
                StatCard(label: "7 days", cost: manager.weekStats.totalCost, messages: manager.weekStats.totalMessages, icon: "calendar", accent: .blue)
                StatCard(label: "30 days", cost: manager.monthStats.totalCost, messages: manager.monthStats.totalMessages, icon: "calendar.badge.clock", accent: .purple)
            }

            // Sparkline chart
            if manager.monthStats.daily.count >= 2 {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("USAGE TREND")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(1)
                            Spacer()
                            Text("7 days")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.6))
                        }

                        SparklineView(
                            data: Array(manager.monthStats.daily.prefix(7).reversed().map(\.cost))
                        )
                        .frame(height: 48)
                    }
                }
            }

            // Model breakdown
            if !manager.monthStats.byModel.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MODELS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1)

                        ForEach(manager.monthStats.byModel) { model in
                            ModelRow(model: model, totalCost: manager.monthStats.totalCost)
                        }
                    }
                }
            }

            // Daily history
            if !manager.monthStats.daily.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DAILY HISTORY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1)

                        ForEach(manager.monthStats.daily.prefix(7)) { day in
                            HStack(spacing: 8) {
                                Text(day.dateLabel)
                                    .font(.system(size: 10, weight: .medium))
                                    .frame(width: 65, alignment: .leading)
                                DailyBar(cost: day.cost, maxCost: maxDailyCost)
                                Text(formatCost(day.cost))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                PillButton(
                    label: copiedFeedback ? "Copied!" : "Copy",
                    icon: copiedFeedback ? "checkmark" : "doc.on.doc",
                    style: copiedFeedback ? .success : .secondary
                ) {
                    if manager.copyStatsToClipboard() {
                        copiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copiedFeedback = false }
                        }
                    }
                }

                PillButton(label: "Export CSV", icon: "square.and.arrow.up", style: .secondary) {
                    manager.exportCSV()
                }

                Spacer()
            }
        }
    }

    private var maxDailyCost: Double {
        manager.monthStats.daily.prefix(7).map(\.cost).max() ?? 1
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.15), lineWidth: 3)
                    .frame(width: 36, height: 36)
                ProgressView()
                    .controlSize(.small)
                    .tint(.purple)
            }
            Text("Fetching usage...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorView(_ error: String) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(error)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Check settings for details")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.08))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.purple.opacity(0.5))
            }
            Text("Click Refresh to load data")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(action: { manager.refresh() }) {
                HStack(spacing: 5) {
                    if manager.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
                    }
                    Text("Refresh")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(!manager.isAuthenticated || manager.isLoading
                              ? Color.clear
                              : Color.purple.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .foregroundColor(manager.isLoading ? .secondary : .purple)
            .disabled(!manager.isAuthenticated || manager.isLoading)

            Spacer()

            Text("v\(UsageManager.currentVersion)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.35))

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
}

// MARK: - Glass Card

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Tab Pill

struct TabPill: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isActive ? .purple : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.purple.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .purple : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : (isActive ? 0.08 : 0.04)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - Pill Button

enum PillButtonStyle {
    case primary, secondary, success
}

struct PillButton: View {
    let label: String
    var icon: String = ""
    var style: PillButtonStyle = .primary
    let action: () -> Void
    @State private var isHovered = false

    private var fgColor: Color {
        switch style {
        case .primary: return .purple
        case .secondary: return .secondary
        case .success: return .green
        }
    }

    private var bgColor: Color {
        switch style {
        case .primary: return .purple.opacity(isHovered ? 0.18 : 0.1)
        case .secondary: return Color.primary.opacity(isHovered ? 0.1 : 0.05)
        case .success: return .green.opacity(isHovered ? 0.18 : 0.1)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(fgColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(bgColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - Settings section wrapper

struct SettingsSection<Content: View>: View {
    let title: String
    var icon: String = ""
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.purple.opacity(0.7))
                }
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            content
        }
    }
}

// MARK: - Circular Gauge

struct CircularGauge: View {
    let quota: UsageQuota
    var isHovered: Bool = false

    private let lineWidth: CGFloat = 5
    private var progress: Double { min(quota.utilization / 100, 1.0) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Track
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: lineWidth)
                    .frame(width: 52, height: 52)

                // Progress arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [quota.level.color.opacity(0.5), quota.level.color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * progress)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: quota.level.color.opacity(0.3), radius: isHovered ? 6 : 2)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)

                // Percentage text
                Text("\(Int(quota.utilization))")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(quota.level.color)
                + Text("%")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(quota.level.color.opacity(0.7))
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)

            VStack(spacing: 1) {
                Image(systemName: quota.icon)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(quota.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat Card (enhanced cost card)

struct StatCard: View {
    let label: String
    let cost: Double
    let messages: Int
    var icon: String = ""
    var accent: Color = .purple
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(accent.opacity(0.6))

            Text(cost >= 1 ? String(format: "$%.2f", cost) : String(format: "$%.3f", cost))
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text("\(messages) msgs")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(isHovered ? 0.15 : 0.05), lineWidth: 0.5)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: ModelUsage
    let totalCost: Double

    private var fraction: Double {
        guard totalCost > 0 else { return 0 }
        return model.cost / totalCost
    }

    private var color: Color {
        if model.model.contains("opus") { return .purple }
        if model.model.contains("sonnet") { return .blue }
        if model.model.contains("haiku") { return .green }
        return .gray
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 18)

            Text(model.shortName)
                .font(.system(size: 11, weight: .semibold))

            // Proportion bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.04))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.4))
                        .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 4)

            Text(model.cost >= 0.01 ? String(format: "$%.2f", model.cost) : String(format: "$%.3f", model.cost))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 50, alignment: .trailing)
        }
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
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.5), .purple.opacity(0.8)],
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
                let y = geo.size.height - (CGFloat((val - minVal) / range) * (geo.size.height - 8)) - 4
                return CGPoint(x: x, y: y)
            }

            ZStack {
                if points.count >= 2 {
                    // Gradient fill
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        path.addLine(to: points[0])
                        for i in 1..<points.count {
                            let prev = points[i - 1]
                            let curr = points[i]
                            let midX = (prev.x + curr.x) / 2
                            path.addCurve(to: curr,
                                          control1: CGPoint(x: midX, y: prev.y),
                                          control2: CGPoint(x: midX, y: curr.y))
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Smooth curve
                    Path { path in
                        path.move(to: points[0])
                        for i in 1..<points.count {
                            let prev = points[i - 1]
                            let curr = points[i]
                            let midX = (prev.x + curr.x) / 2
                            path.addCurve(to: curr,
                                          control1: CGPoint(x: midX, y: prev.y),
                                          control2: CGPoint(x: midX, y: curr.y))
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [.purple.opacity(0.6), .purple], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }

                // End dot (latest)
                if let last = points.last {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.2))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 5, height: 5)
                    }
                    .position(last)
                }
            }
        }
    }
}
