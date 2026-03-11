// UsageManager.swift
// Orchestrates usage data: API calls, stats, preferences, notifications

import Foundation
import Combine
import SwiftUI
import UserNotifications
import ServiceManagement
import WidgetKit

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

// MARK: - Menu bar display mode

enum MenuBarDisplayMode: Int, CaseIterable, Identifiable {
    case iconOnly = 0
    case percentage = 1
    case percentageAndTimer = 2
    case allQuotas = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .iconOnly: return "Icon"
        case .percentage: return "Session"
        case .percentageAndTimer: return "Timer"
        case .allQuotas: return "All"
        }
    }

    var description: String {
        switch self {
        case .iconOnly: return "C"
        case .percentage: return "C 15%"
        case .percentageAndTimer: return "C 15% · 2h31m"
        case .allQuotas: return "C 15% | 31% | 22%"
        }
    }
}

// MARK: - Alert rule model

struct AlertRule: Identifiable, Codable {
    var id = UUID()
    var quotaLabel: String  // e.g. "Opus (7d)", "Session (5h)"
    var threshold: Double   // 0-100
    var notified: Bool = false
}

// MARK: - Session annotation model

struct SessionAnnotation: Codable {
    var starred: Bool = false
    var tag: String = ""
}

// MARK: - Multi-account model

struct AccountInfo: Identifiable, Codable {
    var id = UUID()
    var label: String       // e.g. "Work", "Personal"
    var credentialsPath: String
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

    /// Shared instance for AppIntents / Shortcuts access
    static var shared: UsageManager!

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

    // MARK: - Live session cost

    @Published var activeSessionCost: Double = 0
    @Published var activeSessionMessages: Int = 0

    // MARK: - Session stats

    @Published var todayStats = UsageStats()
    @Published var weekStats = UsageStats()
    @Published var monthStats = UsageStats()
    @Published var showStats = false
    @Published var isLoadingStats = false
    @Published var sessionHistory: [SessionInfo] = []

    // MARK: - Active session detection

    @Published var isSessionActive = false

    // MARK: - Per-project budgets

    @Published var projectBudgets: [String: Double] {
        didSet {
            if let data = try? JSONEncoder().encode(projectBudgets) {
                UserDefaults.standard.set(data, forKey: "projectBudgets")
            }
        }
    }

    // MARK: - Custom alert rules

    @Published var customAlertRules: [AlertRule] {
        didSet {
            if let data = try? JSONEncoder().encode(customAlertRules) {
                UserDefaults.standard.set(data, forKey: "customAlertRules")
            }
        }
    }

    // MARK: - Session annotations

    @Published var sessionAnnotations: [String: SessionAnnotation] {
        didSet {
            if let data = try? JSONEncoder().encode(sessionAnnotations) {
                UserDefaults.standard.set(data, forKey: "sessionAnnotations")
            }
        }
    }

    // MARK: - Multi-account

    @Published var accounts: [AccountInfo] {
        didSet {
            if let data = try? JSONEncoder().encode(accounts) {
                UserDefaults.standard.set(data, forKey: "accounts")
            }
        }
    }
    @Published var activeAccountIndex: Int {
        didSet {
            UserDefaults.standard.set(activeAccountIndex, forKey: "activeAccountIndex")
        }
    }

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

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "menuBarDisplayMode")
            setupCountdownTimer()
        }
    }

    @Published var dailyBudget: Double {
        didSet {
            UserDefaults.standard.set(dailyBudget, forKey: "dailyBudget")
        }
    }

    // MARK: - Propriétés calculées

    var primaryQuota: UsageQuota? {
        quotas.first(where: { $0.label.contains("Session") }) ?? quotas.first
    }

    /// The quota with the highest utilization (worst state)
    private var worstQuota: UsageQuota? {
        quotas.max(by: { $0.utilization < $1.utilization })
    }

    var menuBarTitle: String {
        switch menuBarDisplayMode {
        case .iconOnly:
            return ""
        case .percentage:
            guard let q = primaryQuota else { return "—" }
            return "\(Int(q.utilization))%"
        case .percentageAndTimer:
            guard let q = primaryQuota else { return "—" }
            let timer = timeUntilReset == "—" ? "" : " · \(timeUntilReset)"
            return "\(Int(q.utilization))%\(timer)"
        case .allQuotas:
            if quotas.isEmpty { return "—" }
            return quotas.map { "\(Int($0.utilization))%" }.joined(separator: " | ")
        }
    }

    var menuBarIcon: String {
        guard let q = worstQuota else { return "c.circle" }
        switch q.level {
        case .critical: return "c.circle.fill"
        case .warning: return "c.circle.fill"
        case .good: return "c.circle"
        }
    }

    /// Secondary color hint for distinguishing warning (half-fill) from critical
    var menuBarIconOpacity: Double {
        guard let q = worstQuota else { return 1.0 }
        switch q.level {
        case .critical: return 1.0
        case .warning: return 0.7
        case .good: return 1.0
        }
    }

    var menuBarIconColor: Color {
        guard let q = worstQuota else { return .primary }
        return q.level.color
    }

    var nextResetDate: Date? {
        quotas.compactMap(\.resetsAt)
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
    }

    // MARK: - Burn rate prediction

    var burnRatePrediction: String? {
        guard let sessionQuota = quotas.first(where: { $0.label.contains("Session") }),
              let resetsAt = sessionQuota.resetsAt,
              sessionQuota.utilization > 5 else { return nil }

        let windowDuration: TimeInterval = 5 * 3600 // 5-hour window
        let timeRemaining = resetsAt.timeIntervalSinceNow
        let timeElapsed = windowDuration - timeRemaining

        guard timeElapsed > 300 else { return nil } // Need at least 5 min of data

        let ratePerSecond = sessionQuota.utilization / timeElapsed
        guard ratePerSecond > 0 else { return nil }

        let remainingPercent = 100 - sessionQuota.utilization
        let secondsToLimit = remainingPercent / ratePerSecond

        if secondsToLimit > 24 * 3600 { return nil } // More than a day, not useful

        let hours = Int(secondsToLimit) / 3600
        let minutes = (Int(secondsToLimit) % 3600) / 60

        if hours > 0 {
            return "~\(hours)h \(minutes)m"
        }
        return "~\(minutes)m"
    }

    // MARK: - Model advisor

    var modelAdvisorTip: String? {
        let sonnet = quotas.first(where: { $0.label.contains("Sonnet") })
        let opus = quotas.first(where: { $0.label.contains("Opus") })

        if let s = sonnet, let o = opus {
            if s.utilization > 80 && o.utilization < 50 {
                return "Sonnet quota high — consider using Opus"
            }
            if o.utilization > 80 && s.utilization < 50 {
                return "Opus quota high — consider using Sonnet"
            }
        }

        if let session = quotas.first(where: { $0.label.contains("Session") }),
           session.utilization > 90 {
            return "Session almost full — pace usage or wait for reset"
        }

        return nil
    }

    // MARK: - Daily budget

    var budgetUtilization: Double? {
        guard dailyBudget > 0 else { return nil }
        return min((todayStats.totalCost / dailyBudget) * 100, 100)
    }

    // MARK: - Private

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let maxRetries = 5
    private var rateLimitedUntil: Date?

    private var countdownTimer: AnyCancellable?
    private var autoRefreshTimer: AnyCancellable?
    private var activeSessionTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var isRefreshingToken = false
    private var statsWorkItem: DispatchWorkItem?

    // Track previous quota utilizations for reset detection
    private var previousQuotaUtilizations: [String: Double] = [:]

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
        let savedDisplayMode = UserDefaults.standard.integer(forKey: "menuBarDisplayMode")
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedDisplayMode) ?? .percentageAndTimer
        self.dailyBudget = UserDefaults.standard.double(forKey: "dailyBudget")

        // Load per-project budgets
        if let data = UserDefaults.standard.data(forKey: "projectBudgets"),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.projectBudgets = decoded
        } else {
            self.projectBudgets = [:]
        }

        // Load custom alert rules
        if let data = UserDefaults.standard.data(forKey: "customAlertRules"),
           let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) {
            self.customAlertRules = decoded
        } else {
            self.customAlertRules = []
        }

        // Load session annotations
        if let data = UserDefaults.standard.data(forKey: "sessionAnnotations"),
           let decoded = try? JSONDecoder().decode([String: SessionAnnotation].self, from: data) {
            self.sessionAnnotations = decoded
        } else {
            self.sessionAnnotations = [:]
        }

        // Load accounts
        if let data = UserDefaults.standard.data(forKey: "accounts"),
           let decoded = try? JSONDecoder().decode([AccountInfo].self, from: data) {
            self.accounts = decoded
        } else {
            self.accounts = []
        }
        self.activeAccountIndex = UserDefaults.standard.integer(forKey: "activeAccountIndex")

        // Forward objectWillChange from sub-managers
        auth.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        updater.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        auth.loadCredentials()
        auth.startWatchingCredentials()

        // Auto-connect when credentials appear via file watcher
        auth.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.isAuthenticated && self.quotas.isEmpty && !self.isLoading {
                    self.showSettings = false
                    self.refresh()
                }
            }
        }.store(in: &cancellables)

        setupCountdownTimer()
        setupAutoRefresh()
        setupActiveSessionDetection()

        if notificationsEnabled {
            requestNotificationPermission()
        }

        if isAuthenticated {
            refresh()
        }

        refreshStats()
        checkForUpdates()
    }

    // MARK: - Session stats (single-pass optimization)

    func refreshStats() {
        guard !isLoadingStats else { return }
        isLoadingStats = true

        // Cancel any previous in-flight stats work
        statsWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            let cal = Calendar.current
            let now = Date()
            let todayStart = cal.startOfDay(for: now)
            let weekStart = cal.date(byAdding: .day, value: -7, to: now)!
            let monthStart = cal.date(byAdding: .day, value: -30, to: now)!

            let month = SessionAnalyzer.analyze(since: monthStart)
            let week = month.filtered(since: weekStart)
            let today = month.filtered(since: todayStart)

            let sessions = SessionAnalyzer.recentSessions(limit: 15)

            DispatchQueue.main.async {
                self?.todayStats = today
                self?.weekStats = week
                self?.monthStats = month
                self?.sessionHistory = sessions
                self?.isLoadingStats = false
                print("[ClaudeGod] Stats: today=$\(String(format: "%.2f", today.totalCost)) week=$\(String(format: "%.2f", week.totalCost)) month=$\(String(format: "%.2f", month.totalCost)) projects=\(month.byProject.count) sessions=\(sessions.count)")
            }
        }
        statsWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    // MARK: - Active session detection

    private func setupActiveSessionDetection() {
        // Check every 15s for active session (was 10s). Only computes live cost when active.
        activeSessionTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkActiveSession()
            }
    }

    private func checkActiveSession() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            let projectsDir = SessionAnalyzer.projectsDir
            guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else {
                DispatchQueue.main.async {
                    self?.isSessionActive = false
                    self?.activeSessionCost = 0
                    self?.activeSessionMessages = 0
                }
                return
            }

            let now = Date()
            let threshold: TimeInterval = 30

            for dir in dirs {
                guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for file in files where file.pathExtension == "jsonl" {
                    if let attrs = try? fm.attributesOfItem(atPath: file.path),
                       let modDate = attrs[.modificationDate] as? Date,
                       now.timeIntervalSince(modDate) < threshold {
                        // Also compute live session cost
                        let sessionData = SessionAnalyzer.activeSessionCost()
                        DispatchQueue.main.async {
                            self?.isSessionActive = true
                            self?.activeSessionCost = sessionData?.cost ?? 0
                            self?.activeSessionMessages = sessionData?.messages ?? 0
                        }
                        return
                    }
                }
            }
            DispatchQueue.main.async {
                self?.isSessionActive = false
                self?.activeSessionCost = 0
                self?.activeSessionMessages = 0
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

        // Respect rate limit cooldown
        if let until = rateLimitedUntil, Date() < until {
            let remaining = Int(until.timeIntervalSince(Date()))
            if remaining > 0 {
                errorMessage = "Rate limited — retry in \(remaining)s"
                print("[ClaudeGod] Skipping refresh, rate limited for \(remaining)s more")
                return
            }
            rateLimitedUntil = nil
        }

        if auth.tokenNeedsRefresh && auth.refreshToken != nil {
            guard !isRefreshingToken else { return }
            isRefreshingToken = true
            isLoading = true
            errorMessage = nil
            auth.refreshAccessToken { [weak self] success in
                guard let self else { return }
                self.isRefreshingToken = false
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
                    // Store previous utilizations for reset detection
                    for q in self.quotas {
                        self.previousQuotaUtilizations[q.label] = q.utilization
                    }
                    self.parseUsageResponse(data)
                    self.isLoading = false
                    self.lastRefresh = Date()
                    self.refreshStats()
                    self.checkNotifications()
                    self.checkResetNotifications()
                    self.checkCustomAlerts()
                    self.checkProjectBudgets()
                    self.updateWidgetData()

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
                    // Retry-After: 0 usually means stale token, not real rate limit
                    let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let retryAfterValue = retryAfterHeader.flatMap(Double.init) ?? -1
                    let isLikelyStaleToken = retryAfterValue == 0

                    if isLikelyStaleToken && self.auth.refreshToken != nil && retryCount == 0 {
                        // Token likely expired server-side — refresh and retry once
                        print("[ClaudeGod] 429 with Retry-After:0 — likely stale token, refreshing...")
                        self.auth.refreshAccessToken { success in
                            if success {
                                print("[ClaudeGod] Token refreshed, retrying fetch...")
                                self.fetchUsage(retryCount: retryCount + 1)
                            } else {
                                DispatchQueue.main.async {
                                    self.isLoading = false
                                    self.errorMessage = "Session expired — run `claude login`"
                                }
                            }
                        }
                    } else if !self.quotas.isEmpty {
                        // We have cached data — keep it silently
                        self.isLoading = false
                        self.rateLimitedUntil = Date().addingTimeInterval(30)
                        print("[ClaudeGod] Rate limited (429), keeping existing data")
                    } else if retryCount < Self.maxRetries {
                        let delay = 5 * pow(2.0, Double(retryCount))
                        print("[ClaudeGod] Rate limited (429), retrying in \(Int(delay))s (attempt \(retryCount + 1)/\(Self.maxRetries))...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.fetchUsage(retryCount: retryCount + 1)
                        }
                    } else {
                        self.isLoading = false
                        self.errorMessage = "Rate limited — run `claude login` to refresh"
                    }

                default:
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

    private func setupCountdownTimer() {
        countdownTimer?.cancel()
        let interval: TimeInterval = menuBarDisplayMode == .percentageAndTimer ? 1 : 30
        countdownTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateCountdown()
            }
    }

    private func updateCountdown() {
        guard let reset = nextResetDate else {
            if timeUntilReset != "—" { timeUntilReset = "—" }
            return
        }
        let remaining = reset.timeIntervalSinceNow
        if remaining <= 0 {
            if timeUntilReset != "resetting..." {
                timeUntilReset = "resetting..."
                // Auto-refresh after reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.refresh()
                }
            }
            return
        }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let newValue: String
        if menuBarDisplayMode == .percentageAndTimer {
            // Keep menu bar compact: skip seconds when > 1h
            if hours > 0 {
                newValue = "\(hours)h\(String(format: "%02d", minutes))m"
            } else {
                let seconds = Int(remaining) % 60
                newValue = "\(minutes)m\(String(format: "%02d", seconds))s"
            }
        } else {
            newValue = hours > 0
                ? "\(hours)h \(minutes)m"
                : "\(minutes)m"
        }
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
            self?.refreshStats()
        }
    }

    // MARK: - Multi-threshold notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkNotifications() {
        guard notificationsEnabled else { return }

        let customThreshold = 100 - notificationThreshold
        let thresholds = Array(Set([customThreshold, 95])).sorted()

        var updated = notifiedThresholds

        for quota in quotas {
            for threshold in thresholds {
                let key = "\(quota.label)-\(Int(threshold))"

                if quota.utilization >= threshold && !updated.contains(key) {
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
                } else if quota.utilization < threshold - 5 {
                    // Hysteresis: must drop 5% below to re-arm
                    updated.remove(key)
                }
            }
        }

        notifiedThresholds = updated
    }

    // MARK: - Reset notifications

    private func checkResetNotifications() {
        guard notificationsEnabled else { return }

        for quota in quotas {
            if let previousUtil = previousQuotaUtilizations[quota.label],
               previousUtil > 50 && quota.utilization < 10 {
                // Quota just reset
                let content = UNMutableNotificationContent()
                content.title = "Claude God"
                content.body = "\(quota.label) quota reset — you're back to \(Int(quota.utilization))%"
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "reset-\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                UNUserNotificationCenter.current().add(request)
                print("[ClaudeGod] Reset notification sent for \(quota.label)")
            }
        }
    }

    // MARK: - Custom alert rules check

    private func checkCustomAlerts() {
        guard notificationsEnabled else { return }
        for i in customAlertRules.indices {
            let rule = customAlertRules[i]
            if let quota = quotas.first(where: { $0.label == rule.quotaLabel }),
               quota.utilization >= rule.threshold && !rule.notified {
                let content = UNMutableNotificationContent()
                content.title = "Claude God"
                content.body = "\(rule.quotaLabel): \(Int(quota.utilization))% used (alert at \(Int(rule.threshold))%)"
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "custom-alert-\(rule.id.uuidString)",
                    content: content, trigger: nil
                )
                UNUserNotificationCenter.current().add(request)
                customAlertRules[i].notified = true
            } else if let quota = quotas.first(where: { $0.label == rule.quotaLabel }),
                      quota.utilization < rule.threshold - 10 && rule.notified {
                // Hysteresis: must drop 10% below threshold to re-arm
                customAlertRules[i].notified = false
            }
        }
    }

    // MARK: - Per-project budget check

    private func checkProjectBudgets() {
        guard notificationsEnabled else { return }
        for project in monthStats.byProject {
            if let budget = projectBudgets[project.directoryName], budget > 0,
               project.totalCost >= budget {
                let key = "project-budget-\(project.directoryName)"
                if !notifiedThresholds.contains(key) {
                    let content = UNMutableNotificationContent()
                    content.title = "Claude God"
                    content.body = "\(project.projectName): monthly budget exceeded ($\(String(format: "%.2f", project.totalCost)) / $\(String(format: "%.0f", budget)))"
                    content.sound = .default
                    let request = UNNotificationRequest(
                        identifier: key, content: content, trigger: nil
                    )
                    UNUserNotificationCenter.current().add(request)
                    var updated = notifiedThresholds
                    updated.insert(key)
                    notifiedThresholds = updated
                }
            }
        }
    }

    // MARK: - Session annotations

    func toggleStar(sessionID: String) {
        var ann = sessionAnnotations[sessionID] ?? SessionAnnotation()
        ann.starred.toggle()
        sessionAnnotations[sessionID] = ann
    }

    func setTag(sessionID: String, tag: String) {
        var ann = sessionAnnotations[sessionID] ?? SessionAnnotation()
        ann.tag = tag
        sessionAnnotations[sessionID] = ann
    }

    func annotation(for sessionID: String) -> SessionAnnotation {
        sessionAnnotations[sessionID] ?? SessionAnnotation()
    }

    // MARK: - Multi-account

    func addAccount(label: String, path: String) {
        accounts.append(AccountInfo(label: label, credentialsPath: path))
    }

    func switchAccount(index: Int) {
        guard index >= 0 && index < accounts.count else { return }
        activeAccountIndex = index
        auth.loadCredentials()
        // Don't clear quotas — keep old data until new ones arrive
        refresh()
    }

    func removeAccount(at index: Int) {
        guard index >= 0 && index < accounts.count else { return }
        accounts.remove(at: index)
        if activeAccountIndex >= accounts.count {
            activeAccountIndex = max(0, accounts.count - 1)
        }
    }

    // MARK: - Widget data sharing

    private func updateWidgetData() {
        let defaults = UserDefaults(suiteName: "group.com.lcharvol.claude-god") ?? .standard
        let quotaData = quotas.enumerated().map { index, q in
            ["utilization": q.utilization, "labelIndex": Double(index)]
        }
        if let data = try? JSONEncoder().encode(quotaData) {
            defaults.set(data, forKey: "widgetQuotas")
        }
        defaults.set(todayStats.totalCost, forKey: "widgetTodayCost")
        defaults.set(todayStats.totalMessages, forKey: "widgetTodayMessages")

        // Trigger widget reload if available
        if #available(macOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
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

        if !monthStats.byProject.isEmpty {
            lines.append("")
            lines.append("── Projects (30d) ──")
            for p in monthStats.byProject {
                lines.append("\(p.projectName): \(fmt(p.totalCost)) (\(p.totalMessages) msgs)")
            }
        }

        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @Published var csvExportSuccess: Bool?

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "claude-usage-\(Formatters.csvDate.string(from: Date())).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "Date,Cost,Messages,Input Tokens,Output Tokens,Cache Creation,Cache Read\n"
        for day in monthStats.daily.reversed() {
            let dateStr = Formatters.csvDate.string(from: day.date)
            csv += "\(dateStr),\(String(format: "%.4f", day.cost)),\(day.messageCount),"
            csv += "\(day.tokens.inputTokens),\(day.tokens.outputTokens),"
            csv += "\(day.tokens.cacheCreationTokens),\(day.tokens.cacheReadTokens)\n"
        }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            csvExportSuccess = true
        } catch {
            csvExportSuccess = false
            print("[ClaudeGod] CSV export failed: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.csvExportSuccess = nil
        }
    }
}
