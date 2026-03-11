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
                    } else if manager.selectedTab == .analytics {
                        statsView
                    } else if manager.selectedTab == .timeline {
                        timelineView
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
        .frame(width: manager.compactMode && !manager.showSettings && manager.selectedTab == .usage ? 280 : 340)
        .animation(.easeOut(duration: 0.15), value: manager.selectedTab)
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
                HStack(spacing: 5) {
                    Text("Claude God")
                        .font(.system(size: 13, weight: .semibold))
                    if manager.isSessionActive {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .fill(.green.opacity(0.4))
                                    .frame(width: 10, height: 10)
                            )
                            .help("Claude Code is active")
                    }
                }
                if !manager.subscriptionType.isEmpty {
                    Text(manager.subscriptionType.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let lastRefresh = manager.lastRefresh, !manager.showSettings && manager.selectedTab == .usage {
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
                if manager.showSettings { manager.selectedTab = .usage }
            }
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 1) {
            SHTab(label: "Usage", isActive: manager.selectedTab == .usage) {
                manager.selectedTab = .usage
            }
            .keyboardShortcut("1", modifiers: .command)
            SHTab(label: "Analytics", isActive: manager.selectedTab == .analytics) {
                manager.selectedTab = .analytics
            }
            .keyboardShortcut("2", modifiers: .command)
            SHTab(label: "Timeline", isActive: manager.selectedTab == .timeline) {
                manager.selectedTab = .timeline
                if manager.timelineSessions.isEmpty {
                    manager.refreshTimeline()
                }
            }
            .keyboardShortcut("3", modifiers: .command)
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
                            SHBadge(text: "Not connected", color: .orange)
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

            // Daily budget
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Daily budget")
                    HStack(spacing: 8) {
                        Text("$")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("Not set", value: Binding(
                            get: { manager.dailyBudget > 0 ? manager.dailyBudget : nil },
                            set: { manager.dailyBudget = $0 ?? 0 }
                        ), format: .number.precision(.fractionLength(0...2)))
                            .font(.system(size: 12, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("/ day")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        if manager.dailyBudget > 0 {
                            SHButton(label: "Clear", style: .ghost) {
                                manager.dailyBudget = 0
                            }
                        }
                    }
                    if manager.dailyBudget > 0 {
                        Text("Get notified when daily spend approaches your budget")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
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

            // Custom alert rules
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SHLabel("Custom Alerts")
                        Spacer()
                        if !manager.quotas.isEmpty {
                            SHButton(label: "Add", icon: "plus", style: .ghost) {
                                // Pick a quota that doesn't already have a rule at 80%
                                let existing = Set(manager.customAlertRules.map { "\($0.quotaLabel)-\(Int($0.threshold))" })
                                let available = manager.quotas.first(where: { !existing.contains("\($0.label)-80") })
                                let quotaLabel = available?.label ?? manager.quotas.first?.label ?? "Session (5h)"
                                manager.customAlertRules.append(AlertRule(quotaLabel: quotaLabel, threshold: 80))
                            }
                        }
                    }
                    if manager.customAlertRules.isEmpty {
                        Text("No custom alerts. Add one to get notified at specific quota thresholds.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(manager.customAlertRules.enumerated()), id: \.element.id) { index, rule in
                            HStack(spacing: 6) {
                                Text(rule.quotaLabel)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Text("at \(Int(rule.threshold))%")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Button {
                                    manager.customAlertRules.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Multi-account
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SHLabel("Accounts")
                        Spacer()
                        SHButton(label: "Add", icon: "plus", style: .ghost) {
                            let label = manager.accounts.isEmpty ? "Default" : "Account \(manager.accounts.count + 1)"
                            manager.addAccount(label: label, path: AuthManager.credentialsPath.path)
                        }
                    }
                    if manager.accounts.isEmpty {
                        Text("Using default credentials. Add accounts to switch between profiles.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(manager.accounts.enumerated()), id: \.element.id) { index, account in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(index == manager.activeAccountIndex ? Color.green : Theme.border)
                                    .frame(width: 6, height: 6)
                                Text(account.label)
                                    .font(.system(size: 11, weight: index == manager.activeAccountIndex ? .semibold : .regular))
                                Spacer()
                                if index != manager.activeAccountIndex {
                                    SHButton(label: "Switch", style: .ghost) {
                                        manager.switchAccount(index: index)
                                    }
                                }
                                Button {
                                    manager.removeAccount(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
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
                    HStack(spacing: 8) {
                        Text("⌥⌘C Toggle · ⌘R Refresh · ⌘1 Usage · ⌘2 Analytics · ⌘3 Timeline")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    if !HotkeyManager.shared.isRegistered {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 8))
                                .foregroundColor(.orange)
                            Text("⌥⌘C hotkey failed to register")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
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

            // Live session cost
            if manager.isSessionActive && manager.activeSessionCost > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Active session")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(manager.activeSessionMessages) msgs")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(formatCost(manager.activeSessionCost))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.green)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.15), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(Color.green.opacity(0.05))
                        )
                )
            }

            // Burn rate prediction
            if let prediction = manager.burnRatePrediction {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                    Text("At this rate, limit in")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(prediction)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.15), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(Color.orange.opacity(0.05))
                        )
                )
            }

            // Model advisor
            if let tip = manager.modelAdvisorTip {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.yellow)
                    Text(tip)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.15), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(Color.yellow.opacity(0.05))
                        )
                )
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

            if let prediction = manager.burnRatePrediction {
                SHDivider().padding(.vertical, 2)
                HStack {
                    Text("Limit in")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Spacer()
                    Text(prediction)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }
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
                // Cost cards
                HStack(spacing: 6) {
                    SHStatCard(label: "Today", value: formatCost(manager.todayStats.totalCost), sub: "\(manager.todayStats.totalMessages) msgs")
                    SHStatCard(label: "7 days", value: formatCost(manager.weekStats.totalCost), sub: "\(manager.weekStats.totalMessages) msgs")
                    SHStatCard(
                        label: "30 days",
                        value: formatCost(manager.monthStats.totalCost),
                        sub: "\(manager.monthStats.totalMessages) msgs · \(manager.monthStats.sessionCount) sessions"
                    )
                }

                // Daily budget progress
                if let budgetUtil = manager.budgetUtilization {
                    SHCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                SHLabel("Daily Budget")
                                Spacer()
                                Text("\(formatCost(manager.todayStats.totalCost)) / $\(String(format: "%.0f", manager.dailyBudget))")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(budgetUtil >= 100 ? .red : budgetUtil >= 80 ? .orange : .secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Theme.muted)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(budgetUtil >= 100 ? Color.red : budgetUtil >= 80 ? Color.orange : Theme.accent)
                                        .frame(width: max(0, geo.size.width * CGFloat(min(budgetUtil, 100) / 100)))
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }

                // Sparkline
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

                // Models (aggregated by short name)
                if !manager.monthStats.byModel.isEmpty {
                    SHCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SHLabel("Models")
                            ForEach(aggregatedModels) { model in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(colorForModel(model.model))
                                        .frame(width: 6, height: 6)
                                    Text(model.shortName)
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 50, alignment: .leading)
                                    Spacer()
                                    Text(formatTokens(model.tokens.totalTokens))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(formatCostCompact(model.cost))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .frame(width: 64, alignment: .trailing)
                                        .lineLimit(1)
                                }
                            }
                            SHDivider()
                            HStack(spacing: 6) {
                                Text("Total")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 56, alignment: .leading)
                                Spacer()
                                Text(formatTokens(manager.monthStats.totalTokens.totalTokens))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(formatCostCompact(manager.monthStats.totalCost))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 64, alignment: .trailing)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                // Projects with budget
                if !manager.monthStats.byProject.isEmpty {
                    SHCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SHLabel("Projects")
                            ForEach(manager.monthStats.byProject.prefix(5)) { project in
                                VStack(spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundColor(Theme.accent.opacity(0.6))
                                        Text(project.projectName)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(project.totalMessages) msgs")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text(formatCostCompact(project.totalCost))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    // Project budget bar
                                    if let budget = manager.projectBudgets[project.directoryName], budget > 0 {
                                        let util = min(project.totalCost / budget, 1.0)
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 2).fill(Theme.muted)
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(util >= 1.0 ? Color.red : util >= 0.8 ? Color.orange : Theme.accent.opacity(0.5))
                                                    .frame(width: max(0, geo.size.width * CGFloat(util)))
                                            }
                                        }
                                        .frame(height: 3)
                                        .help("\(formatCost(project.totalCost)) / $\(String(format: "%.0f", budget)) monthly budget")
                                    }
                                }
                                .help("\(project.projectName): \(project.sessionCount) sessions · \(project.totalMessages) messages · \(formatCost(project.totalCost))")
                            }
                        }
                    }
                }

                // Week-over-week comparison
                weekComparisonView

                // Efficiency metrics
                efficiencyView

                // Heatmap
                heatmapView

                // Recent sessions (with annotations)
                if !manager.sessionHistory.isEmpty {
                    SHCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SHLabel("Recent Sessions")
                            ForEach(manager.sessionHistory.prefix(5)) { session in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        // Star button
                                        Button {
                                            manager.toggleStar(sessionID: session.id)
                                        } label: {
                                            Image(systemName: manager.annotation(for: session.id).starred ? "star.fill" : "star")
                                                .font(.system(size: 8))
                                                .foregroundColor(manager.annotation(for: session.id).starred ? .yellow : .secondary.opacity(0.4))
                                        }
                                        .buttonStyle(.plain)

                                        Text(session.topic)
                                            .font(.system(size: 10, weight: .medium))
                                            .lineLimit(1)
                                        Spacer()

                                        // Tag
                                        if !manager.annotation(for: session.id).tag.isEmpty {
                                            Text(manager.annotation(for: session.id).tag)
                                                .font(.system(size: 8, weight: .medium))
                                                .foregroundColor(Theme.accent)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(
                                                    Capsule().fill(Theme.accentMuted)
                                                )
                                        }

                                        Text(formatCost(session.cost))
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    }
                                    HStack(spacing: 6) {
                                        Text(session.projectName)
                                            .font(.system(size: 9))
                                            .foregroundColor(Theme.accent.opacity(0.7))
                                        Text("·")
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(session.primaryModel)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text("·")
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(session.durationLabel)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text("·")
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(session.timeLabel)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(session.messageCount) msgs")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if session.id != manager.sessionHistory.prefix(5).last?.id {
                                    SHDivider()
                                }
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

                    SHButton(
                        label: manager.csvExportSuccess == true ? "Saved!" : manager.csvExportSuccess == false ? "Failed" : "CSV",
                        icon: manager.csvExportSuccess == true ? "checkmark" : "square.and.arrow.up",
                        style: manager.csvExportSuccess == true ? .success : .outline
                    ) {
                        manager.exportCSV()
                    }

                    Spacer()
                }
            }
        }
    }

    // MARK: - Week comparison

    @ViewBuilder
    private var weekComparisonView: some View {
        let comp = manager.monthStats.weekComparison
        if comp.thisWeekCost > 0 || comp.lastWeekCost > 0 {
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Week over Week")
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This week")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(formatCost(comp.thisWeekCost))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last week")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(formatCost(comp.lastWeekCost))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Delta")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Image(systemName: comp.costDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(String(format: "%.0f", abs(comp.costDeltaPercent)))%")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(comp.costDelta >= 0 ? .orange : .green)
                        }
                    }
                    // Message delta
                    HStack(spacing: 4) {
                        Text("\(comp.thisWeekMessages) msgs this week")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        if comp.messageDelta != 0 {
                            Text("(\(comp.messageDelta > 0 ? "+" : "")\(comp.messageDelta))")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(comp.messageDelta > 0 ? .orange : .green)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Efficiency metrics

    @ViewBuilder
    private var efficiencyView: some View {
        let eff = manager.monthStats.efficiency(sessionCount: manager.monthStats.sessionCount)
        if manager.monthStats.totalMessages > 0 {
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Efficiency")
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text(eff.costPerMessage >= 0.01 ? String(format: "$%.2f", eff.costPerMessage) : String(format: "$%.3f", eff.costPerMessage))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("$/msg")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle().fill(Theme.border).frame(width: 1, height: 28)

                        VStack(spacing: 2) {
                            Text(formatTokens(eff.avgTokensPerSession))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("tok/session")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle().fill(Theme.border).frame(width: 1, height: 28)

                        VStack(spacing: 2) {
                            Text(String(format: "%.0f%%", eff.cacheHitRate))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            Text("cache hit")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Trend indicator
                    if abs(eff.costPerMessageTrend) > 0.001 {
                        HStack(spacing: 4) {
                            Image(systemName: eff.costPerMessageTrend > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text("Cost/msg \(eff.costPerMessageTrend > 0 ? "increasing" : "decreasing")")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(eff.costPerMessageTrend > 0 ? .orange : .green)
                    }
                }
            }
        }
    }

    // MARK: - Heatmap

    @ViewBuilder
    private var heatmapView: some View {
        let days = manager.monthStats.heatmap(days: 56) // 8 weeks
        if !days.isEmpty {
            SHCard {
                VStack(alignment: .leading, spacing: 6) {
                    SHLabel("Activity")
                    HeatmapGrid(days: days)
                        .frame(height: 62)
                }
            }
        }
    }

    /// Aggregate models by short name (merges e.g. claude-3-opus + claude-opus-4)
    private var aggregatedModels: [ModelUsage] {
        manager.monthStats.aggregatedModels
    }

    private var maxDailyCost: Double {
        manager.monthStats.daily.prefix(dailyRange).map(\.cost).max() ?? 1
    }

    // MARK: - Timeline

    private static let timelineDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM yyyy"
        return f
    }()

    private static let projectColors: [Color] = [
        .purple, .blue, .green, .orange, .pink, .cyan, .yellow, .red
    ]

    private var timelineView: some View {
        VStack(spacing: 10) {
            // Day navigation
            HStack {
                Button(action: { manager.timelineGoToPreviousDay() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.secondary)

                Spacer()

                Text(Self.timelineDateFormatter.string(from: manager.timelineDate))
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Button(action: { manager.timelineGoToNextDay() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Calendar.current.isDateInToday(manager.timelineDate) ? Theme.muted : Color.secondary)
                .disabled(Calendar.current.isDateInToday(manager.timelineDate))
            }
            .padding(.horizontal, 4)

            // Day summary
            if !manager.timelineSessions.isEmpty {
                let totalCost = manager.timelineSessions.reduce(0) { $0 + $1.cost }
                let totalMsgs = manager.timelineSessions.reduce(0) { $0 + $1.messageCount }
                HStack(spacing: 12) {
                    timelineStat(label: "Sessions", value: "\(manager.timelineSessions.count)")
                    timelineStat(label: "Messages", value: "\(totalMsgs)")
                    timelineStat(label: "Cost", value: "$\(String(format: "%.2f", totalCost))")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.muted)
                )
            }

            if manager.isLoadingTimeline {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading sessions...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            } else if manager.timelineSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No sessions this day")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            } else {
                // Session list
                ForEach(manager.timelineSessions) { session in
                    timelineSessionCard(session)
                }
            }
        }
    }

    private func timelineStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @State private var expandedTimelineSessions: Set<String> = []

    private func timelineSessionCard(_ session: TimelineSession) -> some View {
        let isExpanded = expandedTimelineSessions.contains(session.id)
        let projColor = Self.projectColors[session.projectColor % Self.projectColors.count]

        return VStack(spacing: 0) {
            // Session header (always visible)
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isExpanded {
                        expandedTimelineSessions.remove(session.id)
                    } else {
                        expandedTimelineSessions.insert(session.id)
                    }
                }
            }) {
                VStack(alignment: .leading, spacing: 6) {
                    // Time range + project badge
                    HStack(spacing: 6) {
                        // Color bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(projColor)
                            .frame(width: 3, height: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(session.timeRangeLabel)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text("·")
                                    .foregroundColor(.secondary)
                                Text(session.durationLabel)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }

                            Text(session.projectName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(projColor)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("$\(String(format: "%.3f", session.cost))")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            HStack(spacing: 3) {
                                Text("\(session.messageCount) msgs")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("·")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 9))
                                Text(session.primaryModel)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    // Topic
                    Text(session.topic)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(isExpanded ? 3 : 1)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            // Expanded: message list
            if isExpanded {
                SHDivider()
                VStack(spacing: 0) {
                    ForEach(Array(session.messages.enumerated()), id: \.element.id) { index, msg in
                        HStack(spacing: 8) {
                            Text(msg.timeLabel)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .leading)

                            // Model badge
                            Text(msg.shortModel)
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(modelColor(msg.shortModel).opacity(0.15))
                                )
                                .foregroundColor(modelColor(msg.shortModel))

                            Text(msg.topic)
                                .font(.system(size: 9))
                                .foregroundColor(Color.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("$\(String(format: "%.4f", msg.cost))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)

                        if index < session.messages.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.muted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private func modelColor(_ shortModel: String) -> Color {
        switch shortModel {
        case "Opus": return .purple
        case "Sonnet": return .blue
        case "Haiku": return .green
        default: return .secondary
        }
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

    /// Compact cost formatting for tight layouts (no decimals for large amounts)
    private func formatCostCompact(_ cost: Double) -> String {
        if cost >= 1000 { return String(format: "$%.0f", cost) }
        if cost >= 100 { return String(format: "$%.1f", cost) }
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

                    Path { path in
                        path.move(to: CGPoint(x: pt.x, y: 0))
                        path.addLine(to: CGPoint(x: pt.x, y: geo.size.height))
                    }
                    .stroke(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                        .position(pt)

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

// MARK: - Heatmap Grid (GitHub-style)

struct HeatmapGrid: View {
    let days: [HeatmapDay]
    @Environment(\.colorScheme) private var colorScheme

    private let cellSize: CGFloat = 7
    private let spacing: CGFloat = 2

    private var maxCost: Double {
        days.map(\.cost).max() ?? 1
    }

    private func color(for day: HeatmapDay) -> Color {
        let level = day.intensity(maxCost: maxCost)
        let base = Color(red: 0.56, green: 0.39, blue: 0.98)
        switch level {
        case 0: return colorScheme == .dark ? Color.primary.opacity(0.06) : Color.primary.opacity(0.04)
        case 1: return base.opacity(0.25)
        case 2: return base.opacity(0.45)
        case 3: return base.opacity(0.7)
        default: return base.opacity(0.95)
        }
    }

    var body: some View {
        let weeks = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(week) { day in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(for: day))
                                .frame(width: cellSize, height: cellSize)
                                .help(day.cost > 0
                                    ? "\(SessionAnalyzer.dayLabelFormatter.string(from: day.date)): \(day.cost >= 0.01 ? String(format: "$%.2f", day.cost) : String(format: "$%.3f", day.cost)) · \(day.messageCount) msgs"
                                    : "\(SessionAnalyzer.dayLabelFormatter.string(from: day.date)): no activity")
                        }
                    }
                }
            }
            // Legend
            HStack(spacing: 3) {
                Spacer()
                Text("Less")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(level == 0
                            ? (colorScheme == .dark ? Color.primary.opacity(0.06) : Color.primary.opacity(0.04))
                            : Color(red: 0.56, green: 0.39, blue: 0.98).opacity(Double(level) * 0.25))
                        .frame(width: 7, height: 7)
                }
                Text("More")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
}
