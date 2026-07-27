// MenuBarView.swift
// shadcn-inspired UI — flat, minimal, bordered, muted palette

import SwiftUI
import AppKit

// MARK: - Design tokens

/// Multiplier applied to every font size in the popover (see `TextScale`).
struct TextScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var textScale: Double {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

struct ScaledFont: ViewModifier {
    @Environment(\.textScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` scaled by the user's text-size preference.
    /// Every popover font goes through this so one setting resizes the whole UI.
    func shFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }
}

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
    @State private var extensionsSection: ExtensionsSection = .discover
    @State private var openPluginDetail: String?  // plugin id for detail view (e.g. "claude-mem@thedotmack")
    @State private var memorySection: MemorySection = .list
    @AppStorage(UDKey.dailyRange) private var dailyRange: Int = 7

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
                    } else if manager.selectedTab == .roi {
                        roiView
                    } else if manager.selectedTab == .extensions {
                        extensionsView
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
            .frame(minHeight: 0, maxHeight: .infinity)

            ResizeHandle(height: $manager.windowHeight, minHeight: 400, maxHeight: 1400)

            SHDivider()

            // Footer
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        // Width grows with the text scale so larger type doesn't wrap or truncate.
        // It never shrinks below the base width: Settings holds fixed-width controls
        // (pickers, ring preview) whose minimum exceeds a narrowed window, and the
        // overflow gets clipped on both edges.
        .frame(width: (manager.compactMode && !manager.showSettings && manager.selectedTab == .usage ? 300 : 400)
                      * max(manager.textScale.rawValue, 1.0),
               height: manager.windowHeight)
        .environment(\.textScale, manager.textScale.rawValue)
        .background(WindowTopAnchor(height: manager.windowHeight))
        .animation(.easeOut(duration: 0.15), value: manager.selectedTab)
        .animation(.easeOut(duration: 0.15), value: manager.showSettings)
        .onAppear {
            manager.refreshIfStale()
            manager.refreshStatsIfStale()
        }
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
                        .shFont(13, weight: .heavy)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text("Claude God")
                        .shFont(13, weight: .semibold)
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
                        .shFont(11, weight: .medium)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let lastRefresh = manager.lastRefresh, !manager.showSettings && manager.selectedTab == .usage {
                Text(lastRefresh.formatted(date: .omitted, time: .shortened))
                    .shFont(11, weight: .medium, design: .monospaced)
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
            SHTab(label: "ROI", isActive: manager.selectedTab == .roi) {
                manager.selectedTab = .roi
                if manager.roiStats.totalAssistedCommits == 0 && !manager.isLoadingROI {
                    manager.refreshROI()
                }
            }
            .keyboardShortcut("4", modifiers: .command)
            SHTab(label: "Extensions", isActive: manager.selectedTab == .extensions) {
                manager.selectedTab = .extensions
                manager.memoryManager.refresh()
                manager.pluginManager.refresh()
            }
            .keyboardShortcut("5", modifiers: .command)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.muted)
        )
    }

    // MARK: - Update banner

    @State private var copiedBrewCommand = false

    private var updateBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .shFont(14, weight: .medium)
                    .foregroundColor(Theme.accent)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Update available")
                        .shFont(11, weight: .medium)
                    Text("v\(UpdateChecker.currentVersion) → v\(manager.latestVersion)")
                        .shFont(11, weight: .medium, design: .monospaced)
                        .foregroundColor(.secondary)
                }

                Spacer()

                SHButton(label: "Update", style: .primary) {
                    manager.installUpdate()
                }
            }

            // Brew command copy
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew upgrade claude-god", forType: .string)
                copiedBrewCommand = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedBrewCommand = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copiedBrewCommand ? "checkmark" : "doc.on.clipboard")
                        .shFont(10)
                    Text(copiedBrewCommand ? "Copied!" : "brew upgrade claude-god")
                        .shFont(11, design: .monospaced)
                }
                .foregroundColor(copiedBrewCommand ? .green : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
            }
            .buttonStyle(.plain)
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
                    if manager.isAuthenticated && !manager.auth.tokenExpired {
                        HStack(spacing: 8) {
                            SHBadge(text: "Connected", color: .green)
                            Spacer()
                            Text(manager.credentialSource.rawValue)
                                .shFont(11, weight: .medium, design: .monospaced)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            SHBadge(
                                text: manager.isAuthenticated ? "Session expired" : "Not connected",
                                color: .orange
                            )
                            SHButton(
                                label: manager.isAutoReconnecting ? "Signing in..." : "Sign In",
                                icon: manager.isAutoReconnecting ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.plus",
                                style: .outline
                            ) {
                                manager.launchAutoReconnect()
                            }
                            .disabled(manager.isAutoReconnecting)
                            if let session = manager.terminalSession {
                                EmbeddedTerminalView(session: session)
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
                        .shFont(12)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if manager.notificationsEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Alert at")
                                    .shFont(11)
                                    .foregroundColor(.secondary)
                                Text("\(Int(100 - manager.notificationThreshold))% used")
                                    .shFont(11, weight: .semibold, design: .monospaced)
                                Spacer()
                                Text("(\(Int(manager.notificationThreshold))% left)")
                                    .shFont(11, design: .monospaced)
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
                            .shFont(12, weight: .medium)
                            .foregroundColor(.secondary)
                        TextField("Not set", value: Binding(
                            get: { manager.dailyBudget > 0 ? manager.dailyBudget : nil },
                            set: { manager.dailyBudget = $0 ?? 0 }
                        ), format: .number.precision(.fractionLength(0...2)))
                            .shFont(12, design: .monospaced)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("/ day")
                            .shFont(11)
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
                            .shFont(11)
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
                        .shFont(11, weight: .medium, design: .monospaced)
                        .foregroundColor(.secondary)
                }
            }

            // Icon+ ring configuration
            if manager.menuBarDisplayMode == .rings {
                SHCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SHLabel("Icon+ Rings")
                        Text("Choose up to 3 quotas to display as concentric activity rings.")
                            .shFont(11)
                            .foregroundColor(.secondary)

                        let quotaOptions: [String] = manager.ringQuotaOptions.map(\.label)

                        ForEach(0..<3, id: \.self) { i in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(MenuBarRingView.ringColors[i])
                                    .frame(width: 8, height: 8)
                                Text("Ring \(i + 1)")
                                    .shFont(11, weight: .medium)
                                    .frame(width: 44, alignment: .leading)
                                Spacer()
                                let slotBinding = Binding<String>(
                                    get: {
                                        i < manager.ringStatLabels.count
                                            ? manager.ringStatLabels[i] : ""
                                    },
                                    set: { newVal in
                                        var labels = manager.ringStatLabels
                                        while labels.count <= i { labels.append("") }
                                        labels[i] = newVal
                                        manager.ringStatLabels = labels
                                    }
                                )
                                Picker("", selection: slotBinding) {
                                    Text("None").tag("")
                                    if quotaOptions.isEmpty {
                                        Text("Loading…").disabled(true)
                                    } else {
                                        ForEach(quotaOptions, id: \.self) { label in
                                            Text(label).tag(label)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 160)
                            }
                        }

                        Divider()

                        // Live preview
                        RingSettingsPreview(
                            quotas: manager.ringQuotaOptions,
                            labels: manager.ringStatLabels
                        )
                    }
                }
            }

            // Custom alert rules
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SHLabel("Custom Alerts")
                        Spacer()
                        if !manager.allNotifiableQuotas.isEmpty {
                            SHButton(label: "Add", icon: "plus", style: .ghost) {
                                // Pick a quota that doesn't already have a rule at 80%
                                let existing = Set(manager.customAlertRules.map { "\($0.quotaLabel)-\(Int($0.threshold))" })
                                let available = manager.allNotifiableQuotas.first(where: { !existing.contains("\($0.label)-80") })
                                let quotaLabel = available?.label ?? manager.allNotifiableQuotas.first?.label ?? "Session (5h)"
                                manager.customAlertRules.append(AlertRule(quotaLabel: quotaLabel, threshold: 80))
                            }
                        }
                    }
                    if manager.customAlertRules.isEmpty {
                        Text("No custom alerts. Add one to get notified at specific quota thresholds.")
                            .shFont(11)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(manager.customAlertRules.enumerated()), id: \.element.id) { index, rule in
                            HStack(spacing: 6) {
                                Text(rule.quotaLabel)
                                    .shFont(11, weight: .medium)
                                    .lineLimit(1)
                                Spacer()
                                Text("at \(Int(rule.threshold))%")
                                    .shFont(11, design: .monospaced)
                                    .foregroundColor(.secondary)
                                Button {
                                    manager.customAlertRules.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .shFont(11, weight: .bold)
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
                            .shFont(11)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(manager.accounts.enumerated()), id: \.element.id) { index, account in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(index == manager.activeAccountIndex ? Color.green : Theme.border)
                                    .frame(width: 6, height: 6)
                                Text(account.label)
                                    .shFont(11, weight: index == manager.activeAccountIndex ? .semibold : .regular)
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
                                        .shFont(11, weight: .bold)
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
                        .shFont(12)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    SHDivider()
                    HStack {
                        Text("Text size")
                            .shFont(12)
                        Spacer()
                        Picker("", selection: $manager.textScale) {
                            ForEach(TextScale.allCases) { scale in
                                Text(scale.label).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 150 * manager.textScale.rawValue)
                    }

                    SHDivider()
                    Toggle("Launch at login", isOn: $manager.launchAtLogin)
                        .shFont(12)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    SHDivider()
                    Toggle("Auto-reconnect when session expires", isOn: $manager.autoReconnect)
                        .shFont(12)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    if manager.autoReconnect {
                        Text("Automatically opens browser sign-in when your token expires.")
                            .shFont(10)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if manager.auth.tokenExpired {
                        SHButton(
                            label: manager.isAutoReconnecting ? "Reconnecting..." : "Reconnect now",
                            icon: manager.isAutoReconnecting ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.plus",
                            style: .outline
                        ) {
                            manager.launchAutoReconnect()
                        }
                        .disabled(manager.isAutoReconnecting)
                    }
                }
            }

            // About
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("About")
                    HStack(spacing: 8) {
                        Text("Claude God v\(UpdateChecker.currentVersion)")
                            .shFont(11)
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
                            .shFont(11)
                            .foregroundColor(.secondary)
                        Spacer()
                        SHButton(label: "Report issue", icon: "exclamationmark.bubble", style: .ghost) {
                            if let url = URL(string: "https://github.com/Lcharvol/Claude-God/issues") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    if let raw = manager.lastRawAPIResponse {
                        SHButton(label: "Copy raw API response", icon: "doc.on.clipboard", style: .ghost) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(raw, forType: .string)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("⌥⌘C Toggle · ⌘R Refresh · ⌘1 Usage · ⌘2 Analytics · ⌘3 Timeline · ⌘4 ROI")
                            .shFont(11, design: .monospaced)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    if !HotkeyManager.shared.isRegistered {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .shFont(11)
                                .foregroundColor(.orange)
                            Text("⌥⌘C hotkey failed to register")
                                .shFont(11)
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
                                    .shFont(11, weight: .medium)
                                    .foregroundColor(.secondary)
                                Text(quota.label)
                                    .shFont(12, weight: .medium)
                            }
                            Spacer()
                            Text(formatUtilization(quota.utilization))
                                .shFont(13, weight: .bold, design: .monospaced)
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
                                .shFont(11, weight: .medium, design: .monospaced)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Peak / Off-peak indicator
            HStack(spacing: 6) {
                Image(systemName: manager.isPeakHours ? "sun.max.fill" : "moon.stars.fill")
                    .shFont(11, weight: .medium)
                    .foregroundColor(manager.isPeakHours ? .orange : .indigo)
                Text(manager.isPeakHours ? "Peak hours" : "Off-peak")
                    .shFont(11, weight: .medium)
                    .foregroundColor(manager.isPeakHours ? .orange : .indigo)
                Spacer()
                Text(manager.peakTransitionDescription)
                    .shFont(11, design: .monospaced)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder((manager.isPeakHours ? Color.orange : Color.indigo).opacity(0.15), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .fill((manager.isPeakHours ? Color.orange : Color.indigo).opacity(0.05))
                    )
            )
            .help("Peak hours: \(UsageManager.peakHoursDescription) (US Pacific)")

            // Live session cost
            if manager.isSessionActive && manager.activeSessionCost > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Active session")
                        .shFont(11)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(manager.activeSessionMessages) msgs")
                        .shFont(11, design: .monospaced)
                        .foregroundColor(.secondary)
                    Text(formatCost(manager.activeSessionCost))
                        .shFont(12, weight: .semibold, design: .monospaced)
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
                        .shFont(11, weight: .medium)
                        .foregroundColor(.orange)
                    Text("At this rate, limit in")
                        .shFont(11)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(prediction)
                        .shFont(12, weight: .semibold, design: .monospaced)
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

            // Monthly cost forecast
            if let forecast = manager.monthlyForecast {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .shFont(11, weight: .medium)
                        .foregroundColor(.blue)
                    Text("Projected this month")
                        .shFont(11)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatCost(forecast.projected))
                        .shFont(12, weight: .semibold, design: .monospaced)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(Color.blue.opacity(0.05))
                        )
                )
            }

            // Model advisor
            if let tip = manager.modelAdvisorTip {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .shFont(11, weight: .medium)
                        .foregroundColor(.yellow)
                    Text(tip)
                        .shFont(11)
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

            // Extra usage
            if let extra = manager.extraUsage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "plusminus.circle.fill")
                            .shFont(11, weight: .medium)
                            .foregroundColor(extra.isEnabled ? .green : .secondary)
                        Text("Extra usage")
                            .shFont(11, weight: .medium)
                        Spacer()
                        if let util = extra.utilization {
                            Text(formatUtilization(util))
                                .shFont(13, weight: .bold, design: .monospaced)
                                .foregroundColor(UsageLevel(utilization: util).color)
                        } else {
                            SHBadge(text: extra.isEnabled ? "On" : "Off",
                                    color: extra.isEnabled ? .green : .secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Extra usage\(extra.utilization.map { ", \(Int($0)) percent used" } ?? "")")

                    if let util = extra.utilization {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.muted)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(UsageLevel(utilization: util).color)
                                    .frame(width: max(0, geo.size.width * CGFloat(util / 100)))
                                    .animation(.easeOut(duration: 0.6), value: util)
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }

                    HStack {
                        Text("Spent this month")
                            .shFont(11)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(extra.usedFormatted + (extra.currency.map { " \($0)" } ?? ""))
                            .shFont(11, weight: .semibold, design: .monospaced)
                    }
                    HStack {
                        Text("Monthly limit")
                            .shFont(11)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(extra.limitFormatted)
                            .shFont(11, weight: .semibold, design: .monospaced)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.15), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                .fill(Color.green.opacity(0.04))
                        )
                )
            }

            // Reset timer
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .shFont(11, weight: .medium)
                    .foregroundColor(.secondary)
                Text("Next reset")
                    .shFont(11)
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .shFont(12, weight: .semibold, design: .monospaced)
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
                        .shFont(11, weight: .medium)
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
                        .shFont(11, weight: .bold, design: .monospaced)
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
                        .shFont(11)
                        .foregroundColor(.orange)
                    Spacer()
                    Text(prediction)
                        .shFont(11, weight: .semibold, design: .monospaced)
                        .foregroundColor(.orange)
                }
            }

            SHDivider().padding(.vertical, 2)

            HStack {
                Text("Next reset")
                    .shFont(11)
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .shFont(11, weight: .semibold, design: .monospaced)
                    .foregroundColor(.secondary)
            }

            HStack {
                Image(systemName: manager.isPeakHours ? "sun.max.fill" : "moon.stars.fill")
                    .shFont(10)
                    .foregroundColor(manager.isPeakHours ? .orange : .indigo)
                Text(manager.isPeakHours ? "Peak" : "Off-peak")
                    .shFont(11)
                    .foregroundColor(manager.isPeakHours ? .orange : .indigo)
                Spacer()
                Text(manager.peakTransitionDescription)
                    .shFont(11, design: .monospaced)
                    .foregroundColor(.secondary)
            }
            .help("Peak hours: \(UsageManager.peakHoursDescription)")

            if let lastRefresh = manager.lastRefresh {
                HStack {
                    Text("Updated")
                        .shFont(11)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(lastRefresh.formatted(date: .omitted, time: .shortened))
                        .shFont(11, weight: .medium, design: .monospaced)
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
                        .shFont(24, weight: .medium)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No session data found")
                        .shFont(12, weight: .medium)
                        .foregroundColor(.secondary)
                    Text("Analytics appear after using Claude Code.\nData is read from ~/.claude/projects/")
                        .shFont(11)
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
                                    .shFont(11, weight: .semibold, design: .monospaced)
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
                                    .shFont(11)
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
                                        .shFont(11, weight: .medium)
                                        .frame(width: 50, alignment: .leading)
                                    Spacer()
                                    Text(formatTokens(model.tokens.totalTokens))
                                        .shFont(11, design: .monospaced)
                                        .foregroundColor(.secondary)
                                    Text(formatCostCompact(model.cost))
                                        .shFont(11, weight: .semibold, design: .monospaced)
                                        .frame(width: 64, alignment: .trailing)
                                        .lineLimit(1)
                                }
                            }
                            SHDivider()
                            HStack(spacing: 6) {
                                Text("Total")
                                    .shFont(11, weight: .semibold)
                                    .frame(width: 56, alignment: .leading)
                                Spacer()
                                Text(formatTokens(manager.monthStats.totalTokens.totalTokens))
                                    .shFont(11, design: .monospaced)
                                    .foregroundColor(.secondary)
                                Text(formatCostCompact(manager.monthStats.totalCost))
                                    .shFont(11, weight: .bold, design: .monospaced)
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
                                            .shFont(11, weight: .medium)
                                            .foregroundColor(Theme.accent.opacity(0.6))
                                        Text(project.projectName)
                                            .shFont(11, weight: .medium)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(project.totalMessages) msgs")
                                            .shFont(11, design: .monospaced)
                                            .foregroundColor(.secondary)
                                        Text(formatCostCompact(project.totalCost))
                                            .shFont(11, weight: .semibold, design: .monospaced)
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

                // Monthly forecast
                if let forecast = manager.monthlyForecast {
                    SHCard {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .shFont(12)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Monthly Forecast")
                                    .shFont(11, weight: .semibold)
                                    .foregroundColor(.primary.opacity(0.7))
                                Text("\(forecast.daysRemaining) days remaining")
                                    .shFont(11)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(formatCost(forecast.projected))
                                .shFont(14, weight: .bold, design: .monospaced)
                                .foregroundColor(.blue)
                        }
                    }
                }

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
                                                .shFont(11)
                                                .foregroundColor(manager.annotation(for: session.id).starred ? .yellow : .secondary.opacity(0.4))
                                        }
                                        .buttonStyle(.plain)

                                        Text(session.topic)
                                            .shFont(11, weight: .medium)
                                            .lineLimit(1)
                                        Spacer()

                                        // Tag
                                        if !manager.annotation(for: session.id).tag.isEmpty {
                                            Text(manager.annotation(for: session.id).tag)
                                                .shFont(11, weight: .medium)
                                                .foregroundColor(Theme.accent)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(
                                                    Capsule().fill(Theme.accentMuted)
                                                )
                                        }

                                        Text(formatCost(session.cost))
                                            .shFont(11, weight: .semibold, design: .monospaced)
                                    }
                                    HStack(spacing: 6) {
                                        Text(session.projectName)
                                            .shFont(11)
                                            .foregroundColor(Theme.accent.opacity(0.7))
                                        Text("·")
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(session.primaryModel)
                                            .shFont(11)
                                            .foregroundColor(.secondary)
                                        Text("·")
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(session.durationLabel)
                                            .shFont(11)
                                            .foregroundColor(.secondary)
                                        Text("·")
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(session.timeLabel)
                                            .shFont(11)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(session.messageCount) msgs")
                                            .shFont(11)
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
                                        .shFont(11, weight: .medium)
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
                                        .shFont(11, weight: .semibold, design: .monospaced)
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

                    SHButton(
                        label: manager.jsonExportSuccess == true ? "Saved!" : manager.jsonExportSuccess == false ? "Failed" : "JSON",
                        icon: manager.jsonExportSuccess == true ? "checkmark" : "square.and.arrow.up",
                        style: manager.jsonExportSuccess == true ? .success : .outline
                    ) {
                        manager.exportJSON()
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
                                .shFont(11)
                                .foregroundColor(.secondary)
                            Text(formatCost(comp.thisWeekCost))
                                .shFont(13, weight: .bold, design: .monospaced)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last week")
                                .shFont(11)
                                .foregroundColor(.secondary)
                            Text(formatCost(comp.lastWeekCost))
                                .shFont(13, weight: .medium, design: .monospaced)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Delta")
                                .shFont(11)
                                .foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Image(systemName: comp.costDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .shFont(11, weight: .bold)
                                Text("\(String(format: "%.0f", abs(comp.costDeltaPercent)))%")
                                    .shFont(12, weight: .bold, design: .monospaced)
                            }
                            .foregroundColor(comp.costDelta >= 0 ? .orange : .green)
                        }
                    }
                    // Message delta
                    HStack(spacing: 4) {
                        Text("\(comp.thisWeekMessages) msgs this week")
                            .shFont(11)
                            .foregroundColor(.secondary)
                        if comp.messageDelta != 0 {
                            Text("(\(comp.messageDelta > 0 ? "+" : "")\(comp.messageDelta))")
                                .shFont(11, weight: .medium)
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
                                .shFont(11, weight: .bold, design: .monospaced)
                            Text("$/msg")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle().fill(Theme.border).frame(width: 1, height: 28)

                        VStack(spacing: 2) {
                            let totalDuration = manager.sessionHistory.reduce(0.0) { $0 + $1.duration }
                            let costPerMin = totalDuration > 60 ? manager.monthStats.totalCost / (totalDuration / 60) : 0
                            Text(costPerMin >= 0.01 ? String(format: "$%.2f", costPerMin) : String(format: "$%.3f", costPerMin))
                                .shFont(11, weight: .bold, design: .monospaced)
                            Text("$/min")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Rectangle().fill(Theme.border).frame(width: 1, height: 28)

                        VStack(spacing: 2) {
                            Text(String(format: "%.0f%%", eff.cacheHitRate))
                                .shFont(11, weight: .bold, design: .monospaced)
                            Text("cache hit")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // Trend indicator
                    if abs(eff.costPerMessageTrend) > 0.001 {
                        HStack(spacing: 4) {
                            Image(systemName: eff.costPerMessageTrend > 0 ? "arrow.up.right" : "arrow.down.right")
                                .shFont(11, weight: .bold)
                            Text("Cost/msg \(eff.costPerMessageTrend > 0 ? "increasing" : "decreasing")")
                                .shFont(11)
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
                        .shFont(11, weight: .semibold)
                }
                .buttonStyle(.plain)
                .foregroundColor(Color.secondary)

                Spacer()

                Text(Self.timelineDateFormatter.string(from: manager.timelineDate))
                    .shFont(12, weight: .semibold)

                Spacer()

                Button(action: { manager.timelineGoToNextDay() }) {
                    Image(systemName: "chevron.right")
                        .shFont(11, weight: .semibold)
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
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
            } else if manager.timelineSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .shFont(24, weight: .medium)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No sessions this day")
                        .shFont(12, weight: .medium)
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
                .shFont(13, weight: .bold, design: .monospaced)
            Text(label)
                .shFont(11, weight: .medium)
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
                                    .shFont(11, weight: .semibold, design: .monospaced)
                                Text("·")
                                    .foregroundColor(.secondary)
                                Text(session.durationLabel)
                                    .shFont(11, weight: .medium)
                                    .foregroundColor(.secondary)
                            }

                            Text(session.projectName)
                                .shFont(11, weight: .semibold)
                                .foregroundColor(projColor)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("$\(String(format: "%.3f", session.cost))")
                                .shFont(11, weight: .bold, design: .monospaced)
                            HStack(spacing: 3) {
                                Text("\(session.messageCount) msgs")
                                    .shFont(11, weight: .medium)
                                    .foregroundColor(.secondary)
                                Text("·")
                                    .foregroundColor(.secondary)
                                    .shFont(11)
                                Text(session.primaryModel)
                                    .shFont(11, weight: .semibold)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .shFont(11, weight: .semibold)
                            .foregroundColor(.secondary)
                    }

                    // Topic
                    Text(session.topic)
                        .shFont(11)
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
                                .shFont(11, weight: .medium, design: .monospaced)
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .leading)

                            // Model badge
                            Text(msg.shortModel)
                                .shFont(11, weight: .bold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(modelColor(msg.shortModel).opacity(0.15))
                                )
                                .foregroundColor(modelColor(msg.shortModel))

                            Text(msg.topic)
                                .shFont(11)
                                .foregroundColor(Color.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("$\(String(format: "%.4f", msg.cost))")
                                .shFont(11, weight: .medium, design: .monospaced)
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

    // MARK: - ROI View

    @ViewBuilder
    private var roiView: some View {
        if !manager.isGitAvailable {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .shFont(24)
                    .foregroundColor(.orange)
                Text("Git not found")
                    .shFont(13, weight: .semibold)
                Text("Install Git to see your ROI metrics.")
                    .shFont(11)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if manager.isLoadingROI {
            VStack(spacing: 8) {
                ProgressView()
                Text("Analyzing git history...")
                    .shFont(11)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if manager.roiStats.totalAssistedCommits == 0 {
            VStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .shFont(24)
                    .foregroundColor(.secondary)
                Text("No data yet")
                    .shFont(13, weight: .semibold)
                Text("Use Claude Code and commit to see your ROI.\nCommits within 2h of a session are tracked.")
                    .shFont(11)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Refresh") { manager.refreshROI() }
                    .shFont(11)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            roiContent
        }
    }

    @ViewBuilder
    private var roiContent: some View {
        let stats = manager.roiStats
        VStack(alignment: .leading, spacing: 12) {
            // Header stat cards
            HStack(spacing: 8) {
                SHStatCard(label: "Cost (30d)", value: formatCostCompact(stats.totalCost), sub: "\(stats.period) days")
                SHStatCard(label: "Commits", value: "\(stats.totalAssistedCommits)", sub: "\(stats.totalLinesChanged) lines")
                SHStatCard(label: "$/commit", value: formatCostCompact(stats.costPerCommit), sub: formatCostCompact(stats.costPerLine) + "/line")
            }

            // Daily trend sparkline
            if !stats.dailyTrend.isEmpty {
                SHCard {
                    VStack(alignment: .leading, spacing: 6) {
                        SHLabel("30-day trend")
                        roiSparkline(data: stats.dailyTrend)
                    }
                }
            }

            // By project
            if !stats.byProject.isEmpty {
                SHCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SHLabel("Projects")
                        ForEach(stats.byProject.prefix(5)) { project in
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.accent)
                                    .frame(width: 3, height: 20)
                                Text(project.projectName)
                                    .shFont(11, weight: .medium)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(project.assistedCommits)c")
                                    .shFont(11, design: .monospaced)
                                    .foregroundColor(.secondary)
                                Text(formatCostCompact(project.costPerCommit) + "/c")
                                    .shFont(11, weight: .semibold, design: .monospaced)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }

            // By model
            if !stats.byModel.isEmpty {
                SHCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SHLabel("Model efficiency")
                        ForEach(Array(stats.byModel.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Circle()
                                    .fill(modelColor(entry.model))
                                    .frame(width: 8, height: 8)
                                Text(entry.model)
                                    .shFont(11, weight: .medium)
                                    .frame(width: 50, alignment: .leading)
                                Spacer()
                                Text(formatCostCompact(entry.cost))
                                    .shFont(11, design: .monospaced)
                                    .foregroundColor(.secondary)
                                Text(formatCostCompact(entry.avgCostPerCommit) + "/commit")
                                    .shFont(11, weight: .semibold, design: .monospaced)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }

            // Trend summary
            roiTrendSummary(stats: stats)
        }
    }

    private func roiSparkline(data: [(date: Date, cost: Double, commits: Int)]) -> some View {
        let maxCommits = data.map(\.commits).max() ?? 1
        return HStack(alignment: .bottom, spacing: 1) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, entry in
                let height = maxCommits > 0 ? CGFloat(entry.commits) / CGFloat(maxCommits) : 0
                RoundedRectangle(cornerRadius: 1)
                    .fill(entry.commits > 0 ? Theme.accent.opacity(0.7) : Theme.muted)
                    .frame(height: max(2, height * 40))
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func roiTrendSummary(stats: ROIStats) -> some View {
        let trend = stats.dailyTrend
        if trend.count >= 10 {
            let mid = trend.count / 2
            let firstHalf = trend[0..<mid]
            let secondHalf = trend[mid...]
            let firstCommits = firstHalf.reduce(0) { $0 + $1.commits }
            let secondCommits = secondHalf.reduce(0) { $0 + $1.commits }
            let firstCost = firstHalf.reduce(0.0) { $0 + $1.cost }
            let secondCost = secondHalf.reduce(0.0) { $0 + $1.cost }
            let firstCPC = firstCommits > 0 ? firstCost / Double(firstCommits) : 0
            let secondCPC = secondCommits > 0 ? secondCost / Double(secondCommits) : 0

            if firstCPC > 0 {
                let pctChange = ((secondCPC - firstCPC) / firstCPC) * 100
                let improved = pctChange < 0
                HStack {
                    Image(systemName: improved ? "arrow.down.right" : "arrow.up.right")
                        .shFont(11)
                        .foregroundColor(improved ? .green : .orange)
                    Text("Cost/commit \(improved ? "decreased" : "increased") \(String(format: "%.0f", abs(pctChange)))% this month")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading...")
                .shFont(12)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorView(_ error: String) -> some View {
        let isRateLimit = error.contains("Rate limited")
        let isAuth = !isRateLimit && (error.contains("login") || error.contains("expired") || error.contains("authenticated"))
        let isNetwork = error.contains("Network") || error.contains("connection")

        return VStack(spacing: 6) {
            SHCard {
                HStack(spacing: 10) {
                    Image(systemName: isAuth ? "key.fill" : isRateLimit ? "clock.fill" : "exclamationmark.triangle")
                        .shFont(14, weight: .medium)
                        .foregroundColor(isRateLimit ? .blue : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error)
                            .shFont(12, weight: .medium)
                        Text(isAuth ? (manager.isAutoReconnecting ? "Waiting for browser sign-in..." : "Session expired") :
                             isNetwork ? "Check your internet connection" :
                             isRateLimit ? "Will auto-retry shortly" :
                             "Try refreshing or check settings")
                            .shFont(11)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if isAuth {
                        SHButton(
                            label: manager.isAutoReconnecting ? "Signing in..." : "Sign In",
                            icon: manager.isAutoReconnecting ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.plus",
                            style: .outline
                        ) {
                            manager.launchAutoReconnect()
                        }
                        .disabled(manager.isAutoReconnecting)
                    } else {
                        SHButton(label: "Retry", icon: "arrow.clockwise", style: .outline) {
                            manager.refresh()
                        }
                    }
                }
            }
            if isAuth, let session = manager.terminalSession {
                EmbeddedTerminalView(session: session)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .shFont(18, weight: .medium)
                .foregroundColor(.secondary)
            Text("Click Refresh to load data")
                .shFont(12)
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
                .shFont(11, weight: .medium, design: .monospaced)
                .foregroundColor(.secondary.opacity(0.4))

            SHButton(label: "Quit", style: .ghost) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Extensions tab

    private enum ExtensionsSection: String, CaseIterable {
        case discover = "Discover"
        case installed = "Installed"
    }

    // Plugin IDs that have a custom detail UI in the app
    private static let pluginsWithUI: Set<String> = [
        "claude-mem@thedotmack",
        "superpowers@claude-plugins-official",
        "frontend-design@claude-plugins-official",
        "github@claude-plugins-official",
        "swift-lsp@claude-plugins-official",
        "code-review@claude-plugins-official",
        "code-simplifier@claude-plugins-official",
        "context7@claude-plugins-official",
        "playwright@claude-plugins-official",
    ]

    @ViewBuilder
    private var extensionsView: some View {
        if let pluginId = openPluginDetail {
            pluginDetailView(pluginId: pluginId)
        } else {
            extensionsBrowser
        }
    }

    private var extensionsBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top-level section picker
            HStack(spacing: 6) {
                ForEach(ExtensionsSection.allCases, id: \.rawValue) { section in
                    Button {
                        extensionsSection = section
                    } label: {
                        Text(section.rawValue)
                            .shFont(11, weight: extensionsSection == section ? .semibold : .regular)
                            .foregroundColor(extensionsSection == section ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(extensionsSection == section ? Theme.muted : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            switch extensionsSection {
            case .discover:
                discoverView
            case .installed:
                installedPluginsView
            }
        }
    }

    // MARK: - Plugin detail view

    @ViewBuilder
    private func pluginDetailView(pluginId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Back button
            Button {
                openPluginDetail = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .shFont(11, weight: .semibold)
                    Text("Installed")
                        .shFont(11)
                }
                .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)

            // Plugin-specific content
            if pluginId == "claude-mem@thedotmack" {
                memoryDetailView
            } else if pluginId == "superpowers@claude-plugins-official" {
                superpowersDetailView
            } else if pluginId == "frontend-design@claude-plugins-official" {
                frontendDesignDetailView
            } else if pluginId == "github@claude-plugins-official" {
                githubDetailView
            } else if let detail = manager.genericPluginManager.detail(for: pluginId) {
                genericPluginDetailView(detail)
            }
        }
    }

    // MARK: - Memory detail view (claude-mem plugin UI)

    @ViewBuilder
    private var memoryDetailView: some View {
        if !manager.memoryManager.isInstalled {
            memoryInstallView
        } else if manager.memoryManager.isLoading && manager.memoryManager.memories.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading memories...")
                    .shFont(11)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            memoryContentInner
        }
    }

    private var memoryInstallView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .shFont(32)
                .foregroundColor(Theme.accent)

            Text("claude-mem not installed")
                .shFont(13, weight: .semibold)

            Text("Install the claude-mem plugin to give Claude persistent memory across sessions.")
                .shFont(11)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("In Claude Code, run:")
                    Text("/plugin marketplace add thedotmack/claude-mem")
                        .shFont(11.5, design: .monospaced)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                    Text("/plugin install claude-mem")
                        .shFont(11.5, design: .monospaced)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                    Text("Then restart Claude Code.")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                manager.memoryManager.refresh()
            } label: {
                HStack(spacing: 4) {
                    if manager.memoryManager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(manager.memoryManager.isLoading ? "Checking..." : "Check again")
                }
            }
            .shFont(11)
            .disabled(manager.memoryManager.isLoading)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.vertical, 8)
    }

    private enum MemorySection: String, CaseIterable {
        case list = "Memories"
        case activity = "Activity"
        case projects = "Projects"
    }

    private var memoryContentInner: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Stats cards
            HStack(spacing: 8) {
                SHStatCard(label: "Memories", value: "\(manager.memoryManager.stats.totalMemories)", sub: "\(manager.memoryManager.stats.recentCount) this week")
                SHStatCard(label: "Sessions", value: "\(manager.memoryManager.stats.totalSessions)", sub: "\(manager.memoryManager.stats.totalProjects) projects")
            }

            // Section picker + actions
            HStack(spacing: 6) {
                ForEach(MemorySection.allCases, id: \.rawValue) { section in
                    Button {
                        memorySection = section
                    } label: {
                        Text(section.rawValue)
                            .shFont(11, weight: memorySection == section ? .semibold : .regular)
                            .foregroundColor(memorySection == section ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(memorySection == section ? Theme.muted : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Export menu
                Menu {
                    Button {
                        let md = manager.memoryManager.exportAllAsMarkdown()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                    } label: {
                        Label("Copy all as Markdown", systemImage: "doc.on.doc")
                    }
                    if let project = manager.memoryManager.selectedProject {
                        Button {
                            let md = manager.memoryManager.exportProjectAsMarkdown(project: project)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(md, forType: .string)
                        } label: {
                            Label("Copy \(projectDisplayName(project)) as Markdown", systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Refresh
                Button {
                    manager.memoryManager.refresh()
                } label: {
                    if manager.memoryManager.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .shFont(11)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(manager.memoryManager.isLoading)
            }

            // Search + filter (only on list view)
            if memorySection == .list {
                memorySearchBar
            }

            // Content
            switch memorySection {
            case .list:
                memoryListView
            case .activity:
                memoryActivityView
            case .projects:
                memoryProjectsView
            }
        }
    }

    private var memorySearchBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .shFont(11)
                    .foregroundColor(.secondary)
                TextField("Search memories...", text: Binding(
                    get: { manager.memoryManager.searchText },
                    set: { manager.memoryManager.searchText = $0 }
                ))
                    .shFont(11)
                    .textFieldStyle(.plain)
                    .onSubmit { manager.memoryManager.refresh() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.muted)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            )

            if !manager.memoryManager.projects.isEmpty {
                Menu {
                    Button("All projects") {
                        manager.memoryManager.selectedProject = nil
                        manager.memoryManager.refresh()
                    }
                    Divider()
                    ForEach(manager.memoryManager.projects, id: \.self) { project in
                        Button(projectDisplayName(project)) {
                            manager.memoryManager.selectedProject = project
                            manager.memoryManager.refresh()
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .shFont(11)
                        Text(manager.memoryManager.selectedProject.map(projectDisplayName) ?? "All")
                            .shFont(11)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .fill(Theme.muted)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Memory list

    @ViewBuilder
    private var memoryListView: some View {
        if manager.memoryManager.memories.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .shFont(20)
                    .foregroundColor(.secondary)
                Text("No memories found")
                    .shFont(11)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            VStack(spacing: 6) {
                ForEach(manager.memoryManager.memories.prefix(30)) { memory in
                    memoryRow(memory)
                }
                if manager.memoryManager.memories.count > 30 {
                    Text("\(manager.memoryManager.memories.count - 30) more...")
                        .shFont(11)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func memoryRow(_ memory: ClaudeMemory) -> some View {
        SHCard {
            VStack(alignment: .leading, spacing: 4) {
                // Title + actions
                HStack(spacing: 4) {
                    // Type badge
                    Text(memory.type.uppercased())
                        .shFont(11, weight: .bold, design: .monospaced)
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Theme.accent.opacity(0.12))
                        )

                    if let title = memory.title {
                        Text(title)
                            .shFont(11, weight: .semibold)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .shFont(11, design: .monospaced)
                        .foregroundColor(.secondary)

                    // Context menu actions
                    Menu {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(memory.toMarkdown(), forType: .string)
                        } label: {
                            Label("Copy as Markdown", systemImage: "doc.on.doc")
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(memory.text, forType: .string)
                        } label: {
                            Label("Copy text", systemImage: "doc.on.clipboard")
                        }
                        Divider()
                        Button(role: .destructive) {
                            manager.memoryManager.deleteMemory(id: memory.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .shFont(11)
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Subtitle
                if let subtitle = memory.subtitle {
                    Text(subtitle)
                        .shFont(11)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Narrative or text
                if let narrative = memory.narrative {
                    Text(narrative)
                        .shFont(11)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                } else if memory.title == nil {
                    Text(memory.text)
                        .shFont(11)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Facts
                if !memory.facts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(memory.facts.prefix(3), id: \.self) { fact in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .shFont(11)
                                    .foregroundColor(Theme.accent)
                                Text(fact)
                                    .shFont(11)
                                    .lineLimit(1)
                            }
                        }
                        if memory.facts.count > 3 {
                            Text("+\(memory.facts.count - 3) more")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Files
                if !memory.allFiles.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .shFont(11)
                            .foregroundColor(.secondary)
                        ForEach(memory.allFiles.prefix(3), id: \.self) { file in
                            Button {
                                openFileInFinder(file)
                            } label: {
                                Text((file as NSString).lastPathComponent)
                                    .shFont(11, design: .monospaced)
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                        if memory.allFiles.count > 3 {
                            Text("+\(memory.allFiles.count - 3)")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Tags row
                HStack(spacing: 4) {
                    if let project = memory.project {
                        memoryTag(projectDisplayName(project), icon: "folder")
                    }
                    if !memory.concepts.isEmpty {
                        ForEach(memory.concepts.prefix(2), id: \.self) { concept in
                            memoryTag(concept, icon: "tag")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Activity timeline

    private var memoryActivityView: some View {
        memoryActivityContent(
            activity: manager.memoryManager.dailyActivity
        )
    }

    private func memoryActivityContent(activity: [DailyActivity]) -> some View {
        let maxCount = activity.map(\.count).max() ?? 1
        let filled = filledActivity(activity)
        let total = activity.map(\.count).reduce(0, +)
        let activeDays = activity.filter { $0.count > 0 }.count

        return VStack(alignment: .leading, spacing: 8) {
            SHLabel("Last 30 days")

            if activity.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .shFont(20)
                        .foregroundColor(.secondary)
                    Text("No activity yet")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                // Activity bar chart
                SHCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(filled) { day in
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(day.count > 0 ? Theme.accent : Theme.muted)
                                        .frame(height: max(2, CGFloat(day.count) / CGFloat(maxCount) * 60))
                                }
                                .frame(maxWidth: .infinity)
                                .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.count) observations")
                            }
                        }
                        .frame(height: 64)

                        HStack {
                            Text("30d ago")
                                .shFont(11)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Today")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    memoryStatItem(value: "\(total)", label: "observations")
                    memoryStatItem(value: "\(activeDays)", label: "active days")
                    memoryStatItem(value: String(format: "%.1f", Double(total) / max(1, Double(activeDays))), label: "avg/day")
                }
            }
        }
    }

    private func filledActivity(_ activity: [DailyActivity]) -> [DailyActivity] {
        guard let first = activity.first else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: first.date)
        let lookup = Dictionary(uniqueKeysWithValues: activity.map {
            (calendar.startOfDay(for: $0.date), $0.count)
        })

        var result: [DailyActivity] = []
        var current = start
        while current <= today {
            result.append(DailyActivity(date: current, count: lookup[current] ?? 0))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? today.addingTimeInterval(86400)
        }
        return result
    }

    private func memoryStatItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .shFont(13, weight: .semibold, design: .monospaced)
            Text(label)
                .shFont(11)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Project summaries

    @ViewBuilder
    private var memoryProjectsView: some View {
        if manager.memoryManager.projectSummaries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "folder")
                    .shFont(20)
                    .foregroundColor(.secondary)
                Text("No projects found")
                    .shFont(11)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            VStack(spacing: 6) {
                ForEach(manager.memoryManager.projectSummaries) { summary in
                    projectSummaryRow(summary)
                }
            }
        }
    }

    private func projectSummaryRow(_ summary: ProjectSummary) -> some View {
        SHCard {
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack {
                    Image(systemName: "folder.fill")
                        .shFont(11)
                        .foregroundColor(Theme.accent)
                    Text(summary.displayName)
                        .shFont(11, weight: .semibold)
                    Spacer()
                    Text("\(summary.totalObservations) obs")
                        .shFont(11, design: .monospaced)
                        .foregroundColor(.secondary)
                }

                // Last active
                Text("Last active: \(summary.lastActive.formatted(date: .abbreviated, time: .omitted))")
                    .shFont(11)
                    .foregroundColor(.secondary)

                // Key facts
                if !summary.allFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Key facts")
                            .shFont(11, weight: .semibold)
                            .foregroundColor(.secondary)
                        ForEach(summary.allFacts.prefix(5), id: \.self) { fact in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .shFont(11)
                                    .foregroundColor(Theme.accent)
                                Text(fact)
                                    .shFont(11)
                                    .lineLimit(1)
                            }
                        }
                        if summary.allFacts.count > 5 {
                            Text("+\(summary.allFacts.count - 5) more facts")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Concepts
                if !summary.allConcepts.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(summary.allConcepts.prefix(4), id: \.self) { concept in
                            memoryTag(concept, icon: "tag")
                        }
                        if summary.allConcepts.count > 4 {
                            Text("+\(summary.allConcepts.count - 4)")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Files
                if !summary.allFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Files (\(summary.allFiles.count))")
                            .shFont(11, weight: .semibold)
                            .foregroundColor(.secondary)
                        ForEach(summary.allFiles.prefix(5), id: \.self) { file in
                            Button {
                                openFileInFinder(file)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text")
                                        .shFont(11)
                                    Text((file as NSString).lastPathComponent)
                                        .shFont(11, design: .monospaced)
                                        .lineLimit(1)
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        if summary.allFiles.count > 5 {
                            Text("+\(summary.allFiles.count - 5) more files")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Actions
                HStack(spacing: 8) {
                    Button {
                        manager.memoryManager.selectedProject = summary.project
                        memorySection = .list
                        manager.memoryManager.refresh()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet")
                                .shFont(11)
                            Text("View memories")
                                .shFont(11)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)

                    Button {
                        let md = manager.memoryManager.exportProjectAsMarkdown(project: summary.project)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                                .shFont(11)
                            Text("Copy Markdown")
                                .shFont(11)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)

                    Button {
                        openFileInFinder(summary.project)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .shFont(11)
                            Text("Open in Finder")
                                .shFont(11)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Superpowers detail view

    private var superpowersDetailView: some View {
        superpowersDetailContent(
            sm: manager.superpowersManager
        )
    }

    private func superpowersDetailContent(sm: SuperpowersManager) -> some View {
        let skills = sm.skills
        let plans = sm.plans
        let specs = sm.specs

        return VStack(alignment: .leading, spacing: 12) {
            // Header stats
            HStack(spacing: 8) {
                SHStatCard(label: "Skills", value: "\(skills.count)", sub: "v\(sm.pluginVersion)")
                SHStatCard(label: "Plans", value: "\(plans.count)", sub: "\(specs.count) specs")
            }

            // Skills list
            SHLabel("Skills")
            VStack(spacing: 4) {
                ForEach(skills) { skill in
                    superpowersSkillRow(skill)
                }
            }

            // Plans
            if !plans.isEmpty {
                SHLabel("Plans")
                VStack(spacing: 4) {
                    ForEach(plans) { plan in
                        superpowersPlanRow(plan)
                    }
                }
            }

            // Specs
            if !specs.isEmpty {
                SHLabel("Specs")
                VStack(spacing: 4) {
                    ForEach(specs) { spec in
                        superpowersSpecRow(spec)
                    }
                }
            }
        }
    }

    private func superpowersSkillRow(_ skill: SuperpowersSkill) -> some View {
        SHCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(skill.displayName)
                        .shFont(11, weight: .semibold)
                    Spacer()
                    memoryTag(skill.category, icon: "tag")
                }

                Text(skill.description)
                    .shFont(11)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                            .shFont(11)
                        Text("\(skill.lineCount) lines")
                            .shFont(11)
                    }
                    .foregroundColor(.secondary)

                    if skill.supportingFiles > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                                .shFont(11)
                            Text("+\(skill.supportingFiles) files")
                                .shFont(11)
                        }
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        openFileInFinder(skill.path)
                    } label: {
                        Image(systemName: "folder")
                            .shFont(11)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func superpowersPlanRow(_ plan: SuperpowersPlan) -> some View {
        SHCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(plan.title)
                        .shFont(11, weight: .semibold)
                        .lineLimit(1)
                    Spacer()
                    Text(plan.date)
                        .shFont(11, design: .monospaced)
                        .foregroundColor(.secondary)
                }

                if plan.totalSteps > 0 {
                    HStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Theme.muted)
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(plan.progress >= 1 ? Color.green : Theme.accent)
                                    .frame(width: geo.size.width * plan.progress, height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text("\(plan.completedSteps)/\(plan.totalSteps)")
                            .shFont(11, design: .monospaced)
                            .foregroundColor(.secondary)

                        Button {
                            openFileInFinder(plan.path)
                        } label: {
                            Image(systemName: "folder")
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func superpowersSpecRow(_ spec: SuperpowersSpec) -> some View {
        SHCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.title)
                        .shFont(11, weight: .semibold)
                        .lineLimit(1)
                    Text(spec.date)
                        .shFont(11, design: .monospaced)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    openFileInFinder(spec.path)
                } label: {
                    Image(systemName: "folder")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Frontend Design detail view

    private var frontendDesignDetailView: some View {
        frontendDesignContent(fm: manager.frontendDesignManager)
    }

    private func frontendDesignContent(fm: FrontendDesignManager) -> some View {
        let principles = fm.principles
        let antiPatterns = fm.antiPatterns
        let tones = fm.tones

        return VStack(alignment: .leading, spacing: 12) {
            // Description
            Text(fm.description)
                .shFont(11)
                .foregroundColor(.secondary)
                .lineLimit(3)

            // Design principles
            SHLabel("Design Principles")
            VStack(spacing: 4) {
                ForEach(principles) { principle in
                    SHCard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: principle.icon)
                                .shFont(12)
                                .foregroundColor(Theme.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(principle.name)
                                    .shFont(11, weight: .semibold)
                                Text(principle.description)
                                    .shFont(11)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }

            // Aesthetic tones
            SHLabel("Aesthetic Tones")
            SHCard {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(tones, id: \.self) { tone in
                        Text(tone)
                            .shFont(11)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Theme.muted)
                            )
                    }
                }
            }

            // Anti-patterns
            SHLabel("Anti-Patterns")
            SHCard {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(antiPatterns) { pattern in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .shFont(11)
                                .foregroundColor(.red.opacity(0.7))
                            Text(pattern.text)
                                .shFont(11)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Cookbook link
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/anthropics/claude-cookbooks/blob/main/coding/prompting_for_frontend_aesthetics.ipynb")!)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book")
                        .shFont(11)
                    Text("Frontend Aesthetics Cookbook")
                        .shFont(11)
                }
                .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - GitHub plugin detail view

    private var githubDetailView: some View {
        githubDetailContent(gm: manager.githubPluginManager)
    }

    private func githubDetailContent(gm: GitHubPluginManager) -> some View {
        let tools = gm.tools
        let categories = gm.categories

        return VStack(alignment: .leading, spacing: 12) {
            // Auth status
            SHCard {
                HStack(spacing: 8) {
                    Image(systemName: gm.isAuthenticated ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .shFont(14)
                        .foregroundColor(gm.isAuthenticated ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gm.isAuthenticated ? "Authenticated" : "Token not found")
                            .shFont(11, weight: .semibold)
                        Text(gm.isAuthenticated ? "GitHub MCP server ready" : "Set GITHUB_PERSONAL_ACCESS_TOKEN")
                            .shFont(10)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(tools.count) tools")
                        .shFont(10, design: .monospaced)
                        .foregroundColor(.secondary)
                }
            }

            // Tools by category
            ForEach(categories, id: \.self) { category in
                githubCategorySection(category: category, tools: tools.filter { $0.category == category })
            }
        }
    }

    private func githubCategorySection(category: String, tools: [GitHubTool]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: tools.first?.icon ?? "wrench")
                    .shFont(10)
                    .foregroundColor(Theme.accent)
                SHLabel(category)
                Text("(\(tools.count))")
                    .shFont(10)
                    .foregroundColor(.secondary)
            }

            SHCard {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tools) { tool in
                        HStack(alignment: .top, spacing: 6) {
                            Text(tool.name)
                                .shFont(10, design: .monospaced)
                                .foregroundColor(Theme.accent)
                                .lineLimit(1)
                            Spacer()
                            Text(tool.description)
                                .shFont(10)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Generic plugin detail view

    private func genericPluginDetailView(_ detail: PluginDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            SHCard {
                HStack(spacing: 8) {
                    Image(systemName: detail.isInstalled ? "checkmark.circle.fill" : "circle")
                        .shFont(14)
                        .foregroundColor(detail.isInstalled ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(detail.name)
                                .shFont(11, weight: .semibold)
                            Text(detail.type.rawValue)
                                .shFont(10, design: .monospaced)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Theme.muted)
                                )
                        }
                        Text(detail.description)
                            .shFont(10)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            // Features
            SHLabel("Features")
            VStack(spacing: 4) {
                ForEach(detail.features) { feature in
                    SHCard {
                        HStack(spacing: 8) {
                            Image(systemName: feature.icon)
                                .shFont(12)
                                .foregroundColor(Theme.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.name)
                                    .shFont(11, weight: .semibold)
                                Text(feature.description)
                                    .shFont(10)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Discover view (plugin marketplace)

    private var discoverView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search bar
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .shFont(11)
                    .foregroundColor(.secondary)
                TextField("Search plugins...", text: Binding(
                    get: { manager.pluginManager.searchText },
                    set: { manager.pluginManager.searchText = $0 }
                ))
                    .shFont(11)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.muted)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
            )

            // Category filter
            if !manager.pluginManager.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        categoryChip("All", isSelected: manager.pluginManager.selectedCategory == nil) {
                            manager.pluginManager.selectedCategory = nil
                        }
                        ForEach(manager.pluginManager.categories, id: \.self) { cat in
                            categoryChip(cat.capitalized, isSelected: manager.pluginManager.selectedCategory == cat) {
                                manager.pluginManager.selectedCategory = cat
                            }
                        }
                    }
                }
            }

            // Plugin list
            if manager.pluginManager.isLoading && manager.pluginManager.availablePlugins.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading plugins...")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else if manager.pluginManager.filteredPlugins.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .shFont(20)
                        .foregroundColor(.secondary)
                    Text("No plugins found")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 6) {
                    ForEach(manager.pluginManager.filteredPlugins) { plugin in
                        pluginCard(plugin)
                    }
                }
            }
        }
    }

    private func pluginCard(_ plugin: MarketplacePlugin) -> some View {
        SHCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(plugin.name)
                                .shFont(11, weight: .semibold)
                            Text("v\(plugin.version)")
                                .shFont(11, design: .monospaced)
                                .foregroundColor(.secondary)
                        }
                        Text(plugin.marketplace)
                            .shFont(11)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    pluginActionButton(plugin)
                }

                Text(plugin.description)
                    .shFont(11)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if !plugin.category.isEmpty {
                        memoryTag(plugin.displayCategory.capitalized, icon: "square.grid.2x2")
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                            .shFont(11)
                        Text(PluginManager.formatInstallCount(plugin.installCount))
                            .shFont(11)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func pluginActionButton(_ plugin: MarketplacePlugin) -> some View {
        if manager.pluginManager.isInstalling == plugin.id {
            ProgressView()
                .controlSize(.small)
        } else if plugin.isInstalled {
            Text("Installed")
                .shFont(11, weight: .medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.muted)
                )
        } else {
            Button {
                manager.pluginManager.installPlugin(plugin)
            } label: {
                Text("Install")
                    .shFont(11, weight: .semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.accent)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func categoryChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .shFont(11, weight: isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Theme.muted : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Theme.border, lineWidth: isSelected ? 0 : 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Installed plugins view

    @ViewBuilder
    private var installedPluginsView: some View {
        let installed = manager.pluginManager.installedPlugins
        let featured = installed.filter { Self.pluginsWithUI.contains($0.id) }
        let others = installed.filter { !Self.pluginsWithUI.contains($0.id) }

        return Group {
            if installed.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .shFont(20)
                        .foregroundColor(.secondary)
                    Text("No plugins installed")
                        .shFont(11)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                VStack(spacing: 10) {
                    // Featured: plugins with custom UI
                    if !featured.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(featured) { plugin in
                                featuredPluginCard(plugin)
                            }
                        }
                    }

                    // Other installed plugins
                    if !others.isEmpty {
                        if !featured.isEmpty {
                            SHDivider()
                        }
                        VStack(spacing: 6) {
                            ForEach(others) { plugin in
                                installedPluginRow(plugin)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Featured plugin card (plugins with custom UI in the app)

    private func featuredPluginCard(_ plugin: MarketplacePlugin) -> some View {
        Button {
            if plugin.id == "claude-mem@thedotmack" {
                manager.memoryManager.refresh()
            } else if plugin.id == "superpowers@claude-plugins-official" {
                manager.superpowersManager.refresh()
            } else if plugin.id == "frontend-design@claude-plugins-official" {
                manager.frontendDesignManager.refresh()
            } else if plugin.id == "github@claude-plugins-official" {
                manager.githubPluginManager.refresh()
            } else {
                manager.genericPluginManager.refresh()
            }
            openPluginDetail = plugin.id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: pluginIcon(for: plugin.id))
                            .shFont(16)
                            .foregroundColor(Theme.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(plugin.name)
                                .shFont(12, weight: .semibold)
                                .foregroundColor(.primary)
                            Text("v\(plugin.installedVersion ?? plugin.version)")
                                .shFont(11, design: .monospaced)
                                .foregroundColor(.secondary)
                        }
                        Text(plugin.description)
                            .shFont(11)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Open arrow
                    Image(systemName: "chevron.right")
                        .shFont(11, weight: .semibold)
                        .foregroundColor(Theme.accent)
                }

                // Status bar
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(plugin.isEnabled ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(plugin.isEnabled ? "Enabled" : "Disabled")
                            .shFont(11)
                            .foregroundColor(.secondary)
                    }

                    if !plugin.category.isEmpty {
                        memoryTag(plugin.displayCategory.capitalized, icon: "square.grid.2x2")
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { plugin.isEnabled },
                        set: { manager.pluginManager.togglePlugin(plugin, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.muted)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func pluginIcon(for pluginId: String) -> String {
        switch pluginId {
        case "claude-mem@thedotmack": return "brain"
        case "superpowers@claude-plugins-official": return "bolt.fill"
        case "frontend-design@claude-plugins-official": return "paintbrush.fill"
        case "github@claude-plugins-official": return "arrow.triangle.branch"
        case "swift-lsp@claude-plugins-official": return "swift"
        case "code-review@claude-plugins-official": return "eye"
        case "code-simplifier@claude-plugins-official": return "wand.and.stars"
        case "context7@claude-plugins-official": return "book.closed"
        case "playwright@claude-plugins-official": return "theatermasks"
        default: return "puzzlepiece.extension"
        }
    }

    // MARK: - Regular installed plugin row

    private func installedPluginRow(_ plugin: MarketplacePlugin) -> some View {
        SHCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(plugin.name)
                                .shFont(11, weight: .semibold)
                            Text("v\(plugin.installedVersion ?? plugin.version)")
                                .shFont(11, design: .monospaced)
                                .foregroundColor(.secondary)
                        }
                        if !plugin.category.isEmpty {
                            memoryTag(plugin.displayCategory.capitalized, icon: "square.grid.2x2")
                        }
                    }
                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { plugin.isEnabled },
                        set: { manager.pluginManager.togglePlugin(plugin, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }

                Text(plugin.description)
                    .shFont(11)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    if let installed = plugin.installedVersion, installed != plugin.version {
                        Button {
                            manager.pluginManager.updatePlugin(plugin)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .shFont(11)
                                Text("Update to v\(plugin.version)")
                                    .shFont(11)
                            }
                            .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if manager.pluginManager.isInstalling == plugin.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            manager.pluginManager.uninstallPlugin(plugin)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "trash")
                                    .shFont(11)
                                Text("Uninstall")
                                    .shFont(11)
                            }
                            .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Memory helpers

    private func memoryTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .shFont(11)
            Text(text)
                .shFont(11)
                .lineLimit(1)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.muted)
        )
    }

    private func projectDisplayName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func openFileInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Try to open parent directory
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.activateFileViewerSelecting([parent])
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
        let totalMinutes = Int(remaining) / 60
        let minutes = totalMinutes % 60
        let totalHours = totalMinutes / 60
        let hours = totalHours % 24
        let days = totalHours / 24
        if days > 0 {
            if hours > 0 { return "in \(days)d \(hours)h" }
            return "in \(days)d"
        }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }
}

// ============================================================
// MARK: - Embedded Terminal
// ============================================================

struct EmbeddedTerminalView: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack(spacing: 6) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 8, height: 8)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 8, height: 8)
                Text("claude auth login")
                    .shFont(10, weight: .medium, design: .monospaced)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if session.isRunning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("running")
                            .shFont(9, weight: .medium)
                            .foregroundColor(.green.opacity(0.8))
                    }
                } else {
                    Text("done")
                        .shFont(9, weight: .medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4))

            Divider().background(Color.white.opacity(0.08))

            // Output
            ScrollViewReader { proxy in
                ScrollView {
                    Text(session.output.isEmpty ? " " : session.output)
                        .shFont(11, design: .monospaced)
                        .foregroundColor(.green.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("bottom")
                }
                .onChange(of: session.output) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .frame(height: 130)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
            .shFont(11, weight: .semibold)
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
                .shFont(11, weight: .medium)
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
                .shFont(11, weight: isActive ? .semibold : .medium)
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
                .shFont(11, weight: .medium)
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
                        .shFont(11, weight: .semibold)
                }
                Text(label)
                    .shFont(11, weight: .medium)
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
                .shFont(11, weight: .medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .shFont(14, weight: .bold, design: .monospaced)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: value)
            if !sub.isEmpty {
                Text(sub)
                    .shFont(11)
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
                                .shFont(11, weight: .medium)
                                .foregroundColor(.secondary)
                        }
                        Text(formatCost(data[idx]))
                            .shFont(11, weight: .bold, design: .monospaced)
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
                    .shFont(11)
                    .foregroundColor(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(level == 0
                            ? (colorScheme == .dark ? Color.primary.opacity(0.06) : Color.primary.opacity(0.04))
                            : Color(red: 0.56, green: 0.39, blue: 0.98).opacity(Double(level) * 0.25))
                        .frame(width: 7, height: 7)
                }
                Text("More")
                    .shFont(11)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Resize handle

/// A small drag handle inserted into the popover layout. SwiftUI's `.frame(height:)`
/// already drives the MenuBarExtra(.window) panel height, so dragging this handle
/// makes the popover grow / shrink directly — no NSWindow style-mask hackery.
struct ResizeHandle: View {
    @Binding var height: Double
    let minHeight: Double
    let maxHeight: Double

    @State private var dragStartHeight: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.secondary.opacity(isHovering ? 0.55 : 0.25))
                .frame(width: 32, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.resizeUpDown.push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStartHeight ?? height
                    if dragStartHeight == nil { dragStartHeight = start }
                    let proposed = start + Double(value.translation.height)
                    height = max(minHeight, min(maxHeight, proposed))
                }
                .onEnded { _ in
                    dragStartHeight = nil
                }
        )
    }
}

// MARK: - Window top-edge anchor

/// Pins the top edge of the MenuBarExtra window to the status-bar item when height
/// changes. Without this, SwiftUI resizes from the window's center point in Release
/// builds, causing the popover to grow/shrink from both the top and bottom.
struct WindowTopAnchor: NSViewRepresentable {
    let height: Double

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Defer so the SwiftUI layout pass has already applied the new frame size.
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let current = window.frame
            guard abs(current.height - height) > 0.5 else { return }
            // Keep the top edge (maxY) fixed; adjust origin.y downward as height grows.
            let newOriginY = current.maxY - height
            window.setFrame(
                NSRect(x: current.origin.x, y: newOriginY,
                       width: current.width, height: height),
                display: false,
                animate: false
            )
        }
    }
}
