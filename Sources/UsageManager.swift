// UsageManager.swift
// Orchestrates usage data: API calls, stats, preferences, notifications

import Foundation
import Combine
import SwiftUI
import UserNotifications
import ServiceManagement

// MARK: - Intervalle d'auto-refresh

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case oneMin = 60
    case twoMin = 120
    case fiveMin = 300
    case tenMin = 600

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .oneMin: return "1 min"
        case .twoMin: return "2 min"
        case .fiveMin: return "5 min"
        case .tenMin: return "10 min"
        }
    }
}

// MARK: - Seuils de couleur partagés

enum UsageLevel {
    case good, warning, critical

    init(utilization: Double) {
        if utilization < 50 { self = .good }
        else if utilization < 80 { self = .warning }
        else { self = .critical }
    }

    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - Quota model

struct UsageQuota: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let utilization: Double      // 0-100
    let resetsAt: Date?

    var level: UsageLevel { UsageLevel(utilization: utilization) }
}

// MARK: - OAuth API response (Codable)

private struct OAuthUsageResponse: Decodable {
    let fiveHour: QuotaData?
    let sevenDay: QuotaData?
    let sevenDaySonnet: QuotaData?
    let sevenDayOpus: QuotaData?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
    }
}

private struct QuotaData: Decodable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

// MARK: - Static formatters

private enum Formatters {
    static let resetDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let resetDateNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let csvDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parseISO(_ string: String) -> Date? {
        resetDate.date(from: string) ?? resetDateNoFrac.date(from: string)
    }
}

// MARK: - Manager principal

class UsageManager: ObservableObject {

    // MARK: - Sub-managers

    let auth = AuthManager()
    let updater = UpdateChecker()

    // MARK: - Forwarding (AuthManager)

    var isAuthenticated: Bool { auth.isAuthenticated }
    var credentialSource: CredentialSource { auth.credentialSource }
    var subscriptionType: String { auth.subscriptionType }
    static var currentVersion: String { UpdateChecker.currentVersion }

    func loadCredentials() {
        auth.loadCredentials()
    }

    // MARK: - Forwarding (UpdateChecker)

    var updateAvailable: Bool { updater.updateAvailable }
    var latestVersion: String { updater.latestVersion }

    func installUpdate() { updater.install() }
    func checkForUpdates() { updater.check() }

    // MARK: - Données d'utilisation

    @Published var quotas: [UsageQuota] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefresh: Date?
    @Published var timeUntilReset: String = "—"

    // MARK: - Session stats

    @Published var todayStats = UsageStats()
    @Published var weekStats = UsageStats()
    @Published var monthStats = UsageStats()
    @Published var showStats = false

    // MARK: - État de l'interface

    @Published var showSettings = false

    // MARK: - Préférences

    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            setupAutoRefresh()
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
            if notificationsEnabled { requestNotificationPermission() }
        }
    }

    @Published var notificationThreshold: Double {
        didSet {
            UserDefaults.standard.set(notificationThreshold, forKey: "notificationThreshold")
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    @Published var compactMode: Bool {
        didSet {
            UserDefaults.standard.set(compactMode, forKey: "compactMode")
        }
    }

    // MARK: - Propriétés calculées

    var primaryQuota: UsageQuota? {
        quotas.first(where: { $0.label.contains("Session") }) ?? quotas.first
    }

    var menuBarTitle: String {
        guard let q = primaryQuota else { return "—" }
        return "\(Int(q.utilization))%"
    }

    var menuBarIcon: String {
        guard let q = primaryQuota else { return "c.circle" }
        switch q.level {
        case .critical: return "c.circle.fill"
        case .warning: return "c.circle.fill"
        case .good: return "c.circle"
        }
    }

    var menuBarIconColor: Color {
        guard let q = primaryQuota else { return .primary }
        return q.level.color
    }

    var nextResetDate: Date? {
        quotas.compactMap(\.resetsAt)
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
    }

    // MARK: - Private

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let maxRetries = 3

    private var countdownTimer: AnyCancellable?
    private var autoRefreshTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    // Multi-threshold notification tracking (persisted)
    private var notifiedThresholds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "notifiedThresholds") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "notifiedThresholds") }
    }

    // MARK: - Initialisation

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .twoMin
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.notificationThreshold = UserDefaults.standard.object(forKey: "notificationThreshold") as? Double ?? 20.0
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.compactMode = UserDefaults.standard.bool(forKey: "compactMode")

        // Forward objectWillChange from sub-managers
        auth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        updater.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        auth.loadCredentials()

        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateCountdown()
            }

        setupAutoRefresh()

        if notificationsEnabled {
            requestNotificationPermission()
        }

        if isAuthenticated {
            refresh()
        }

        refreshStats()
        checkForUpdates()
    }

    // MARK: - Session stats

    func refreshStats() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cal = Calendar.current
            let now = Date()
            let todayStart = cal.startOfDay(for: now)
            let weekStart = cal.date(byAdding: .day, value: -7, to: now)!
            let monthStart = cal.date(byAdding: .day, value: -30, to: now)!

            let today = SessionAnalyzer.analyze(since: todayStart)
            let week = SessionAnalyzer.analyze(since: weekStart)
            let month = SessionAnalyzer.analyze(since: monthStart)

            DispatchQueue.main.async {
                self?.todayStats = today
                self?.weekStats = week
                self?.monthStats = month
                print("[ClaudeGod] Stats: today=$\(String(format: "%.2f", today.totalCost)) week=$\(String(format: "%.2f", week.totalCost)) month=$\(String(format: "%.2f", month.totalCost))")
            }
        }
    }

    // MARK: - Actions

    func refresh() {
        guard !isLoading else { return }
        guard isAuthenticated, auth.accessToken != nil else {
            errorMessage = "Not authenticated — run `claude login` in Terminal"
            return
        }

        if auth.tokenNeedsRefresh && auth.refreshToken != nil {
            isLoading = true
            errorMessage = nil
            auth.refreshAccessToken { [weak self] success in
                guard let self else { return }
                if success {
                    self.fetchUsage()
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Session expired — run `claude login`"
                    }
                }
            }
            return
        }

        isLoading = true
        errorMessage = nil
        fetchUsage()
    }

    // MARK: - Fetch with retry

    private func fetchUsage(retryCount: Int = 0) {
        guard let token = auth.accessToken else { return }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeGod", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        print("[ClaudeGod] Fetching usage from OAuth API... (attempt \(retryCount + 1))")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error = error {
                    // Retry on network errors with exponential backoff
                    if retryCount < Self.maxRetries {
                        let delay = pow(2.0, Double(retryCount))
                        print("[ClaudeGod] Network error, retrying in \(Int(delay))s: \(error.localizedDescription)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.fetchUsage(retryCount: retryCount + 1)
                        }
                        return
                    }
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    print("[ClaudeGod] Network error (giving up): \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.isLoading = false
                    self.errorMessage = "Invalid response"
                    return
                }

                print("[ClaudeGod] HTTP \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200:
                    guard let data = data else {
                        self.isLoading = false
                        self.errorMessage = "Empty response"
                        return
                    }
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[ClaudeGod] Response: \(raw.prefix(500))")
                    }
                    self.parseUsageResponse(data)
                    self.isLoading = false
                    self.lastRefresh = Date()
                    self.refreshStats()
                    self.checkNotifications()

                case 401, 403:
                    if self.auth.refreshToken != nil {
                        print("[ClaudeGod] Got \(httpResponse.statusCode), attempting token refresh...")
                        self.auth.refreshAccessToken { success in
                            if success {
                                self.fetchUsage()
                            } else {
                                DispatchQueue.main.async {
                                    self.isLoading = false
                                    self.errorMessage = "Session expired — run `claude login`"
                                }
                            }
                        }
                    } else {
                        self.isLoading = false
                        self.errorMessage = "Session expired — run `claude login`"
                    }

                case 429:
                    if !self.quotas.isEmpty {
                        self.isLoading = false
                        print("[ClaudeGod] Rate limited (429), keeping existing data")
                    } else {
                        self.isLoading = false
                        self.errorMessage = "Rate limited — Claude Code may be active"
                    }

                default:
                    // Retry on 5xx errors
                    if httpResponse.statusCode >= 500 && retryCount < Self.maxRetries {
                        let delay = pow(2.0, Double(retryCount))
                        print("[ClaudeGod] Server error \(httpResponse.statusCode), retrying in \(Int(delay))s")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.fetchUsage(retryCount: retryCount + 1)
                        }
                        return
                    }
                    self.isLoading = false
                    self.errorMessage = "Error \(httpResponse.statusCode)"
                    print("[ClaudeGod] Error \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }

    // MARK: - Response parsing (Codable)

    private func parseUsageResponse(_ data: Data) {
        guard let response = try? JSONDecoder().decode(OAuthUsageResponse.self, from: data) else {
            errorMessage = "Failed to parse response"
            return
        }

        var newQuotas: [UsageQuota] = []

        if let fiveHour = response.fiveHour {
            let resetsAt = fiveHour.resetsAt.flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Session (5h)",
                icon: "bolt.fill",
                utilization: fiveHour.utilization,
                resetsAt: resetsAt
            ))
        }

        if let sevenDay = response.sevenDay {
            let resetsAt = sevenDay.resetsAt.flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Weekly (all models)",
                icon: "calendar",
                utilization: sevenDay.utilization,
                resetsAt: resetsAt
            ))
        }

        if let sonnet = response.sevenDaySonnet {
            let resetsAt = sonnet.resetsAt.flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Sonnet (7d)",
                icon: "sparkle",
                utilization: sonnet.utilization,
                resetsAt: resetsAt
            ))
        }

        if let opus = response.sevenDayOpus {
            let resetsAt = opus.resetsAt.flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Opus (7d)",
                icon: "star.fill",
                utilization: opus.utilization,
                resetsAt: resetsAt
            ))
        }

        quotas = newQuotas
        print("[ClaudeGod] Parsed \(newQuotas.count) quotas")
    }

    // MARK: - Countdown

    private func updateCountdown() {
        guard let reset = nextResetDate else {
            if timeUntilReset != "—" { timeUntilReset = "—" }
            return
        }
        let remaining = reset.timeIntervalSinceNow
        if remaining <= 0 {
            timeUntilReset = "now"
            return
        }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        let newValue = hours > 0
            ? "\(hours)h \(minutes)m \(seconds)s"
            : "\(minutes)m \(seconds)s"
        if timeUntilReset != newValue { timeUntilReset = newValue }
    }

    // MARK: - Auto-refresh

    private func setupAutoRefresh() {
        autoRefreshTimer?.cancel()
        autoRefreshTimer = nil

        guard refreshInterval != .off else { return }

        autoRefreshTimer = Timer.publish(
            every: TimeInterval(refreshInterval.rawValue),
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Multi-threshold notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkNotifications() {
        guard notificationsEnabled else { return }

        // User-configured threshold (converted from "remaining %" to "used %") + emergency 95%
        let customThreshold = 100 - notificationThreshold
        let thresholds = Array(Set([customThreshold, 95])).sorted()

        var updated = notifiedThresholds

        for quota in quotas {
            for threshold in thresholds {
                let key = "\(quota.label)-\(Int(threshold))"

                if quota.utilization >= threshold && !updated.contains(key) {
                    // Send notification
                    let content = UNMutableNotificationContent()
                    content.title = "Claude God"
                    if threshold >= 95 {
                        content.body = "\(quota.label): \(Int(quota.utilization))% used — almost at limit!"
                    } else {
                        content.body = "\(quota.label): \(Int(quota.utilization))% used"
                    }
                    content.sound = .default

                    let request = UNNotificationRequest(
                        identifier: "usage-\(UUID().uuidString)",
                        content: content,
                        trigger: nil
                    )
                    UNUserNotificationCenter.current().add(request)
                    updated.insert(key)
                } else if quota.utilization < threshold {
                    // Reset notification when utilization drops (after quota reset)
                    updated.remove(key)
                }
            }
        }

        notifiedThresholds = updated
    }

    // MARK: - Launch at Login

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently ignore
        }
    }

    // MARK: - Copy & Export

    func copyStatsToClipboard() -> Bool {
        var lines: [String] = ["Claude God — Usage Stats"]
        lines.append("")

        if !quotas.isEmpty {
            lines.append("── Quotas ──")
            for q in quotas {
                lines.append("\(q.label): \(Int(q.utilization))% used")
            }
            lines.append("")
        }

        let fmt: (Double) -> String = { cost in
            cost >= 0.01 ? String(format: "$%.2f", cost) : String(format: "$%.3f", cost)
        }

        lines.append("── Cost (JSONL) ──")
        lines.append("Today: \(fmt(todayStats.totalCost)) (\(todayStats.totalMessages) msgs)")
        lines.append("7 days: \(fmt(weekStats.totalCost)) (\(weekStats.totalMessages) msgs)")
        lines.append("30 days: \(fmt(monthStats.totalCost)) (\(monthStats.totalMessages) msgs)")

        if !monthStats.byModel.isEmpty {
            lines.append("")
            lines.append("── Models (30d) ──")
            for m in monthStats.byModel {
                lines.append("\(m.shortName): \(fmt(m.cost))")
            }
        }

        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "claude-usage-\(Formatters.csvDate.string(from: Date())).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "Date,Cost,Messages,Input Tokens,Output Tokens,Cache Create,Cache Read\n"
        for day in monthStats.daily.reversed() {
            let dateStr = Formatters.csvDate.string(from: day.date)
            csv += "\(dateStr),\(String(format: "%.4f", day.cost)),\(day.messageCount),"
            csv += "\(day.tokens.inputTokens),\(day.tokens.outputTokens),"
            csv += "\(day.tokens.cacheCreationTokens),\(day.tokens.cacheReadTokens)\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
