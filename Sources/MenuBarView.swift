// MenuBarView.swift
// shadcn-inspired UI — flat, minimal, bordered, muted palette

import SwiftUI
import AppKit

// MARK: - Design tokens

private enum Theme {
    static let radius: CGFloat = 8
    static let border = Color.primary.opacity(0.08)
    static let borderHover = Color.primary.opacity(0.15)
    static let muted = Color.primary.opacity(0.04)
    static let mutedHover = Color.primary.opacity(0.08)
    static let accent = Color(red: 0.56, green: 0.39, blue: 0.98)  // indigo-ish
    static let accentMuted = Color(red: 0.56, green: 0.39, blue: 0.98).opacity(0.1)
}

// MARK: - Main view

struct MenuBarView: View {
    @ObservedObject var manager: UsageManager
    @State private var copiedFeedback = false
    @AppStorage("dailyRange") private var dailyRange: Int = 7

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            SHDivider()

            // Tabs
            if manager.isAuthenticated && !manager.showSettings {
                tabBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                SHDivider()
            }

            // Update
            if manager.updateAvailable {
                updateBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            // Content
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
            .frame(minHeight: 300, maxHeight: 600)

            SHDivider()

            // Footer
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: manager.compactMode && !manager.showSettings && !manager.showStats ? 280 : 340)
        .animation(.easeOut(duration: 0.15), value: manager.showStats)
        .animation(.easeOut(duration: 0.15), value: manager.showSettings)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Logo
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 26, height: 26)
                .overlay(
                    Text("C")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 0) {
                Text("Claude God")
                    .font(.system(size: 13, weight: .semibold))
                if !manager.subscriptionType.isEmpty {
                    Text(manager.subscriptionType.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let lastRefresh = manager.lastRefresh, !manager.showSettings && !manager.showStats {
                Text(lastRefresh.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.muted)
                    )
            }

            SHIconButton(icon: manager.showSettings ? "xmark" : "gearshape") {
                manager.showSettings.toggle()
                if manager.showSettings { manager.showStats = false }
            }
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 1) {
            SHTab(label: "Usage", isActive: !manager.showStats) {
                manager.showStats = false
            }
            .keyboardShortcut("1", modifiers: .command)
            SHTab(label: "Analytics", isActive: manager.showStats) {
                manager.showStats = true
            }
            .keyboardShortcut("2", modifiers: .command)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.muted)
        )
    }

    // MARK: - Update banner

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.accent)

            VStack(alignment: .leading, spacing: 0) {
                Text("Update available")
                    .font(.system(size: 11, weight: .medium))
                Text("v\(UpdateChecker.currentVersion) → v\(manager.latestVersion)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            SHButton(label: "Update", style: .primary) {
                manager.installUpdate()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.2), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Theme.accentMuted)
                )
        )
    }

    // MARK: - Settings

    private var settingsView: some View {
        VStack(spacing: 10) {
            // Auth
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Authentication")

                    if manager.isAuthenticated {
                        HStack(spacing: 8) {
                            SHBadge(text: "Connected", color: .green)
                            Spacer()
                            Text(manager.credentialSource.rawValue)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                SHBadge(text: "Not connected", color: .orange)
                            }
                            Text("Run `claude login` in Terminal")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            SHButton(label: "Retry", icon: "arrow.clockwise", style: .outline) {
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

            // Refresh
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Auto-refresh")
                    Picker("Interval", selection: $manager.refreshInterval) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }

            // Notifications
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Notifications")
                    Toggle("Alert when usage is high", isOn: $manager.notificationsEnabled)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if manager.notificationsEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Alert at")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text("\(Int(100 - manager.notificationThreshold))% used")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Spacer()
                                Text("(\(Int(manager.notificationThreshold))% left)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $manager.notificationThreshold, in: 5...50, step: 5)
                                .controlSize(.small)
                        }
                    }
                }
            }

            // Menu bar display
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Menu bar")
                    Picker("Display", selection: $manager.menuBarDisplayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text(manager.menuBarDisplayMode.description)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // Display + System
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Preferences")
                    Toggle("Compact mode", isOn: $manager.compactMode)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    SHDivider()
                    Toggle("Launch at login", isOn: $manager.launchAtLogin)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            // About
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("About")
                    HStack(spacing: 8) {
                        Text("Claude God v\(UpdateChecker.currentVersion)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        SHButton(label: "GitHub", icon: "link", style: .outline) {
                            if let url = URL(string: "https://github.com/Lcharvol/Claude-God") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Free & open source")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        SHButton(label: "Report issue", icon: "exclamationmark.bubble", style: .ghost) {
                            if let url = URL(string: "https://github.com/Lcharvol/Claude-God/issues") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Usage

    private var usageView: some View {
        VStack(spacing: 8) {
            ForEach(manager.quotas) { quota in
                SHCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: quota.icon)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(quota.label)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Text(formatUtilization(quota.utilization))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(quota.level.color)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(quota.label), \(Int(quota.utilization)) percent used")

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.muted)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(quota.level.color)
                                    .frame(width: max(0, geo.size.width * CGFloat(min(quota.utilization, 100) / 100)))
                                    .animation(.easeOut(duration: 0.6), value: quota.utilization)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)

                        if let resetsAt = quota.resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                            Text("Resets \(relativeResetTime(resetsAt))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Reset timer
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Next reset")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.muted)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Next reset \(manager.timeUntilReset)")
        }
    }

    // MARK: - Compact usage

    private var compactUsageView: some View {
        VStack(spacing: 4) {
            ForEach(manager.quotas) { quota in
                HStack(spacing: 6) {
                    Text(quota.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()

                    // Mini bar
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.muted)
                            .frame(width: 44, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(quota.level.color)
                            .frame(width: 44 * CGFloat(min(quota.utilization, 100) / 100), height: 4)
                    }
                    .accessibilityHidden(true)

                    Text(formatUtilization(quota.utilization))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(quota.level.color)
                        .frame(width: 38, alignment: .trailing)
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(quota.label), \(Int(quota.utilization)) percent used")
            }

            SHDivider().padding(.vertical, 2)

            HStack {
                Text("Next reset")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if let lastRefresh = manager.lastRefresh {
                HStack {
                    Text("Updated")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(lastRefresh.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Stats

    private var statsView: some View {
        VStack(spacing: 10) {
            if manager.monthStats.totalMessages == 0 {
                // Empty state
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No session data found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Analytics appear after using Claude Code.\nData is read from ~/.claude/projects/")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Cost cards with session count
                HStack(spacing: 6) {
                    SHStatCard(label: "Today", value: formatCost(manager.todayStats.totalCost), sub: "\(manager.todayStats.totalMessages) msgs")
                    SHStatCard(label: "7 days", value: formatCost(manager.weekStats.totalCost), sub: "\(manager.weekStats.totalMessages) msgs")
                    SHStatCard(
                        label: "30 days",
                        value: formatCost(manager.monthStats.totalCost),
                        sub: "\(manager.monthStats.totalMessages) msgs · \(manager.monthStats.sessionCount) sessions"
                    )
                }

                // Sparkline (follows dailyRange)
                if manager.monthStats.daily.count >= 2 {
                    SHCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SHLabel("Usage Trend")
                                Spacer()
                                Text("\(dailyRange) days")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            SparklineView(
                                data: Array(manager.monthStats.daily.prefix(dailyRange).reversed().map(\.cost)),
                                labels: Array(manager.monthStats.daily.prefix(dailyRange).reversed().map(\.dateLabel))
                            )
                            .frame(height: 50)
                        }
                    }
                }

                // Models
                if !manager.monthStats.byModel.isEmpty {
                    SHCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SHLabel("Models")
                            ForEach(manager.monthStats.byModel) { model in
                                HStack(spacing: 6) {
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
                                        .frame(width: 48, alignment: .trailing)
                                }
                            }
                            SHDivider()
                            HStack(spacing: 6) {
                                Text("Total")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Text(formatTokens(manager.monthStats.totalTokens.totalTokens))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(formatCost(manager.monthStats.totalCost))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                    }
                }

                // Daily with period selector
                if !manager.monthStats.daily.isEmpty {
                    SHCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                SHLabel("Daily")
                                Spacer()
                                Picker("Range", selection: $dailyRange) {
                                    Text("7d").tag(7)
                                    Text("14d").tag(14)
                                    Text("30d").tag(30)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 120)
                                .controlSize(.mini)
                            }
                            ForEach(manager.monthStats.daily.prefix(dailyRange)) { day in
                                HStack(spacing: 6) {
                                    Text(day.dateLabel)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)

                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Theme.muted)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Theme.accent.opacity(0.5))
                                                .frame(width: max(0, geo.size.width * CGFloat(day.cost / maxDailyCost)))
                                        }
                                    }
                                    .frame(height: 5)

                                    Text(formatCost(day.cost))
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .frame(width: 46, alignment: .trailing)
                                }
                                .help("\(day.dateLabel): \(formatCost(day.cost)) · \(day.messageCount) msgs · \(formatTokens(day.tokens.totalTokens)) tokens")
                            }
                        }
                    }
                }

                // Actions
                HStack(spacing: 6) {
                    SHButton(label: "Refresh", icon: manager.isLoadingStats ? nil : "arrow.clockwise", style: .outline, isLoading: manager.isLoadingStats) {
                        manager.refreshStats()
                    }
                    .disabled(manager.isLoadingStats)

                    SHButton(
                        label: copiedFeedback ? "Copied!" : "Copy",
                        icon: copiedFeedback ? "checkmark" : "doc.on.doc",
                        style: copiedFeedback ? .success : .outline
                    ) {
                        if manager.copyStatsToClipboard() {
                            copiedFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedFeedback = false
                            }
                        }
                    }

                    SHButton(label: "CSV", icon: "square.and.arrow.up", style: .outline) {
                        manager.exportCSV()
                    }

                    Spacer()
                }
            }
        }
    }

    private var maxDailyCost: Double {
        manager.monthStats.daily.prefix(dailyRange).map(\.cost).max() ?? 1
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorView(_ error: String) -> some View {
        SHCard {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                    Text("Check settings")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                SHButton(label: "Retry", icon: "arrow.clockwise", style: .outline) {
                    manager.refresh()
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
            Text("Click Refresh to load data")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Footer

    private var bottomBar: some View {
        HStack(spacing: 8) {
            SHButton(label: "Refresh", icon: manager.isLoading ? nil : "arrow.clockwise", style: .ghost, isLoading: manager.isLoading) {
                manager.refresh()
            }
            .disabled(!manager.isAuthenticated || manager.isLoading)
            .keyboardShortcut("r", modifiers: .command)

            Spacer()

            Text("v\(UpdateChecker.currentVersion)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))

            SHButton(label: "Quit", style: .ghost) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Helpers

    private func formatCost(_ cost: Double) -> String {
        if cost >= 0.01 { return String(format: "$%.2f", cost) }
        return String(format: "$%.3f", cost)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func colorForModel(_ model: String) -> Color {
        if model.contains("opus") { return Theme.accent }
        if model.contains("sonnet") { return .blue }
        if model.contains("haiku") { return .green }
        return .gray
    }

    private func formatUtilization(_ value: Double) -> String {
        if value >= 99.5 { return "100%" }
        if value >= 95 { return String(format: "%.1f%%", value) }
        return "\(Int(value))%"
    }

    private func relativeResetTime(_ date: Date) -> String {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return "now" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}

// ============================================================
// MARK: - shadcn-style components
// ============================================================

// MARK: Divider

struct SHDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

// MARK: Card

struct SHCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: Label

struct SHLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.primary.opacity(0.7))
    }
}

// MARK: Badge

struct SHBadge: View {
    let text: String
    var color: Color = .primary

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: Tab

struct SHTab: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                        .shadow(color: isActive ? Color.black.opacity(0.06) : .clear, radius: 1, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Icon Button

struct SHIconButton: View {
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Theme.mutedHover : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isHovered ? Theme.borderHover : Theme.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: Button

enum SHButtonStyle {
    case primary, outline, ghost, success
}

struct SHButton: View {
    let label: String
    var icon: String? = nil
    var style: SHButtonStyle = .primary
    var isLoading: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: style == .ghost ? 0 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        switch style {
        case .primary: return .white
        case .outline: return .primary
        case .ghost: return .secondary
        case .success: return .green
        }
    }

    private var background: Color {
        switch style {
        case .primary: return isHovered ? Theme.accent.opacity(0.9) : Theme.accent
        case .outline: return isHovered ? Theme.mutedHover : Color.clear
        case .ghost: return isHovered ? Theme.mutedHover : Color.clear
        case .success: return .green.opacity(0.08)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary: return Theme.accent
        case .outline: return isHovered ? Theme.borderHover : Theme.border
        case .ghost: return .clear
        case .success: return .green.opacity(0.2)
        }
    }
}

// MARK: Stat Card

struct SHStatCard: View {
    let label: String
    let value: String
    var sub: String = ""

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: value)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)" + (sub.isEmpty ? "" : ", \(sub)"))
    }
}

// MARK: - Sparkline

struct SparklineView: View {
    let data: [Double]
    var labels: [String] = []
    @State private var hoveredIndex: Int?
    @Environment(\.colorScheme) private var colorScheme

    private func formatCost(_ cost: Double) -> String {
        if cost >= 0.01 { return String(format: "$%.2f", cost) }
        return String(format: "$%.3f", cost)
    }

    private var fillOpacity: Double {
        colorScheme == .dark ? 0.2 : 0.1
    }

    @ViewBuilder
    var body: some View {
        if data.count >= 2 {
            sparklineContent
        }
    }

    private var sparklineContent: some View {
        GeometryReader { geo in
            let maxVal = data.max() ?? 1
            let minVal = data.min() ?? 0
            let range = max(maxVal - minVal, 0.001)
            let stepX = geo.size.width / CGFloat(max(data.count - 1, 1))
            let points: [CGPoint] = data.enumerated().map { i, val in
                let x = CGFloat(i) * stepX
                let y = geo.size.height - (CGFloat((val - minVal) / range) * (geo.size.height - 12)) - 6
                return CGPoint(x: x, y: y)
            }

            ZStack {
                if points.count >= 2 {
                    // Fill
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
                    .fill(Theme.accent.opacity(fillOpacity))

                    // Line
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
                    .stroke(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }

                // Hovered point indicator
                if let idx = hoveredIndex, idx < points.count {
                    let pt = points[idx]

                    // Vertical line
                    Path { path in
                        path.move(to: CGPoint(x: pt.x, y: 0))
                        path.addLine(to: CGPoint(x: pt.x, y: geo.size.height))
                    }
                    .stroke(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    // Dot
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .position(pt)

                    // Tooltip
                    VStack(spacing: 1) {
                        if idx < labels.count {
                            Text(labels[idx])
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        Text(formatCost(data[idx]))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                    )
                    .position(x: min(max(pt.x, 25), geo.size.width - 25), y: max(pt.y - 16, 10))
                } else if let last = points.last {
                    // Default end dot when not hovering
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 4, height: 4)
                        .position(last)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let idx = Int((location.x / stepX).rounded())
                    hoveredIndex = min(max(idx, 0), data.count - 1)
                case .ended:
                    hoveredIndex = nil
                }
            }
        }
    }
}
