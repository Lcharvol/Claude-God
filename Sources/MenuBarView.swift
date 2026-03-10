// MenuBarView.swift
// L'interface qui s'affiche quand on clique sur l'icône dans la menu bar

import SwiftUI

// MARK: - Vue principale

struct MenuBarView: View {
    @ObservedObject var manager: UsageManager

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
                if manager.apiKey.isEmpty || manager.showSettings {
                    settingsView
                } else if manager.isLoading && manager.lastRefresh == nil {
                    loadingView
                } else if let error = manager.errorMessage {
                    errorView(error)
                } else if manager.tokensLimit > 0 {
                    usageView
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
        .frame(width: 340)
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

            Text("Claude God")
                .font(.system(size: 14, weight: .bold))

            Spacer()

            if let lastRefresh = manager.lastRefresh, !manager.showSettings {
                HStack(spacing: 3) {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                    Text(lastRefresh.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Button(action: { manager.showSettings.toggle() }) {
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
            SettingsSection(title: "API Key", icon: "key.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("sk-ant-api03-...", text: $manager.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    HStack(spacing: 8) {
                        Button(action: {
                            manager.saveAPIKey()
                            manager.showSettings = false
                            manager.refresh()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Save")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                        .disabled(manager.apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                        if KeychainHelper.load(key: "apiKey") != nil {
                            Button("Delete", role: .destructive) {
                                manager.clearAPIKey()
                            }
                            .controlSize(.small)
                        }

                        Spacer()

                        Group {
                            if manager.apiKeySource != .manual {
                                Label("Auto-detected", systemImage: "sparkles")
                                    .foregroundColor(.purple)
                            } else {
                                Label("Keychain", systemImage: "lock.shield.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .font(.system(size: 10))
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
                    Toggle("Alert when tokens are low", isOn: $manager.notificationsEnabled)
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

            SettingsSection(title: "System", icon: "laptopcomputer") {
                Toggle("Launch at login", isOn: $manager.launchAtLogin)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(.purple)
            }
        }
    }

    // MARK: - Usage

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 14) {
            UsageBar(
                label: "Tokens",
                icon: "text.word.spacing",
                remaining: manager.tokensRemaining,
                limit: manager.tokensLimit,
                percent: manager.tokensPercent,
                level: manager.tokensLevel
            )

            UsageBar(
                label: "Requests",
                icon: "arrow.up.arrow.down",
                remaining: manager.requestsRemaining,
                limit: manager.requestsLimit,
                percent: manager.requestsPercent,
                level: manager.requestsLevel
            )

            // Reset countdown card
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12))
                    .foregroundColor(.purple.opacity(0.8))
                Text("Reset in")
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

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.purple)
            Text("Fetching rate limits...")
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
                Text("Check your API key in settings")
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
                        .fill(manager.apiKey.isEmpty || manager.isLoading
                              ? Color.clear
                              : Color.purple.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .foregroundColor(manager.isLoading ? .secondary : .purple)
            .disabled(manager.apiKey.isEmpty || manager.isLoading)

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

// MARK: - Usage bar component

struct UsageBar: View {
    let label: String
    var icon: String = ""
    let remaining: Int
    let limit: Int
    let percent: Double
    let level: UsageLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    if !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                Text("\(Int(percent))%")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(level.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.06))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [level.color.opacity(0.7), level.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(percent / 100)))
                        .shadow(color: level.color.opacity(0.3), radius: 3, y: 1)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: percent)
                }
            }
            .frame(height: 8)

            Text("\(Formatters.formatNumber(remaining)) / \(Formatters.formatNumber(limit))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}
