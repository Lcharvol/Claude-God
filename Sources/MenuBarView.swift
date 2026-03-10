// MenuBarView.swift
// L'interface qui s'affiche quand on clique sur l'icône dans la menu bar

import SwiftUI

// MARK: - Vue principale

struct MenuBarView: View {
    @ObservedObject var manager: UsageManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Update banner
            if manager.updateAvailable {
                updateBanner
            }

            Divider()

            // Content
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
            .padding(.vertical, 12)

            Divider()

            // Bottom bar
            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                Text("C")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
            }

            Text("Claude God")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if manager.lastRefresh != nil && !manager.showSettings {
                Text(manager.lastRefresh?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Button(action: { manager.showSettings.toggle() }) {
                Image(systemName: manager.showSettings ? "xmark" : "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Update banner

    private var updateBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.purple)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 1) {
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
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.08))
    }

    // MARK: - Settings

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 14) {

            // API Key
            SettingsSection(title: "API Key") {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("sk-ant-api03-...", text: $manager.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                    HStack(spacing: 8) {
                        Button("Save") {
                            manager.saveAPIKey()
                            manager.showSettings = false
                            manager.refresh()
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

                        if manager.apiKeySource != .manual {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                            Text("Auto-detected")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text("Keychain")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Auto-refresh
            SettingsSection(title: "Auto-refresh") {
                Picker("Interval", selection: $manager.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Notifications
            SettingsSection(title: "Notifications") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Alert when tokens are low", isOn: $manager.notificationsEnabled)
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if manager.notificationsEnabled {
                        HStack(spacing: 8) {
                            Text("Threshold")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Slider(value: $manager.notificationThreshold, in: 5...50, step: 5)
                                .controlSize(.small)
                            Text("\(Int(manager.notificationThreshold))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }

            // Launch at Login
            SettingsSection(title: "System") {
                Toggle("Launch at login", isOn: $manager.launchAtLogin)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Usage

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 12) {
            UsageBar(
                label: "Tokens",
                remaining: manager.tokensRemaining,
                limit: manager.tokensLimit,
                percent: manager.tokensPercent
            )

            UsageBar(
                label: "Requests",
                remaining: manager.requestsRemaining,
                limit: manager.requestsLimit,
                percent: manager.requestsPercent
            )

            Divider()

            // Reset countdown
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Reset in")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))

                // Auto-refresh indicator
                if manager.refreshInterval != .off {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                        .foregroundColor(.purple.opacity(0.7))
                        .help("Auto-refresh: \(manager.refreshInterval.label)")
                }
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func errorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Text("Check your API key in settings")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var emptyView: some View {
        Text("Click Refresh to load data")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: { manager.refresh() }) {
                HStack(spacing: 4) {
                    if manager.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text("Refresh")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(manager.isLoading ? .secondary : .purple)
            .disabled(manager.apiKey.isEmpty || manager.isLoading)

            Spacer()

            Text("v1.1")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Settings section wrapper

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.8)
            content
        }
    }
}

// MARK: - Usage bar component

struct UsageBar: View {
    let label: String
    let remaining: Int
    let limit: Int
    let percent: Double

    private var barColor: Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Label row
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                Text("\(Int(percent))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(barColor)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.8), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(percent / 100)))
                        .animation(.easeInOut(duration: 0.6), value: percent)
                }
            }
            .frame(height: 6)

            // Detail
            Text("\(formatNumber(remaining)) / \(formatNumber(limit))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
