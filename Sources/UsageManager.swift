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
    enum Tab: Int { case usage, analytics, timeline, roi }
    @Published var selectedTab: Tab = .usage
    @Published var isLoadingStats = false
    @Published var sessionHistory: [SessionInfo] = []

    // MARK: - Active session detection

    @Published var isSessionActive = false

    // MARK: - Per-project budgets

    @Published var projectBudgets: [String: Double] {
        didSet {
            if let data = try? JSONEncoder().encode(projectBudgets) {
                UserDefaults.standard.set(data, forKey: UDKey.projectBudgets)
            }
        }
    }

    // MARK: - Custom alert rules

    @Published var customAlertRules: [AlertRule] {
        didSet {
            if let data = try? JSONEncoder().encode(customAlertRules) {
                UserDefaults.standard.set(data, forKey: UDKey.customAlertRules)
            }
        }
    }

    // MARK: - Session annotations

    @Published var sessionAnnotations: [String: SessionAnnotation] {
        didSet {
            if let data = try? JSONEncoder().encode(sessionAnnotations) {
                UserDefaults.standard.set(data, forKey: UDKey.sessionAnnotations)
            }
        }
    }

    // MARK: - Multi-account

    @Published var accounts: [AccountInfo] {
        didSet {
            if let data = try? JSONEncoder().encode(accounts) {
                UserDefaults.standard.set(data, forKey: UDKey.accounts)
            }
        }
    }
    @Published var activeAccountIndex: Int {
        didSet {
            UserDefaults.standard.set(activeAccountIndex, forKey: UDKey.activeAccountIndex)
        }
    }

    // MARK: - Timeline

    @Published var timelineSessions: [TimelineSession] = []
    @Published var timelineDate: Date = Date()
    @Published var isLoadingTimeline = false
    @Published var roiStats: ROIStats = .empty
    @Published var isLoadingROI = false
    @Published var isGitAvailable = false

    // MARK: - État de l'interface

    @Published var showSettings = false

    // MARK: - Préférences

    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: UDKey.refreshInterval)
            setupAutoRefresh()
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: UDKey.notificationsEnabled)
            if notificationsEnabled { requestNotificationPermission() }
        }
    }

    @Published var notificationThreshold: Double {
        didSet {
            UserDefaults.standard.set(notificationThreshold, forKey: UDKey.notificationThreshold)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: UDKey.launchAtLogin)
            updateLoginItem()
        }
    }

    @Published var compactMode: Bool {
        didSet {
            UserDefaults.standard.set(compactMode, forKey: UDKey.compactMode)
        }
    }

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: UDKey.menuBarDisplayMode)
            setupCountdownTimer()
        }
    }

    @Published var dailyBudget: Double {
        didSet {
            UserDefaults.standard.set(dailyBudget, forKey: UDKey.dailyBudget)
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

    // MARK: - Monthly cost forecast

    var monthlyForecast: (projected: Double, daysRemaining: Int)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)),
              let daysInMonth = cal.range(of: .day, in: .month, for: today)?.count
        else { return nil }
        let dayOfMonth = cal.component(.day, from: today)
        guard dayOfMonth >= 3 else { return nil } // Need at least 3 days of data

        let costSoFar = monthStats.daily
            .filter { cal.startOfDay(for: $0.date) >= monthStart }
            .reduce(0.0) { $0 + $1.cost }
        guard costSoFar > 0 else { return nil }

        let dailyRate = costSoFar / Double(dayOfMonth)
        let projected = dailyRate * Double(daysInMonth)
        return (projected: projected, daysRemaining: daysInMonth - dayOfMonth)
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

    // MARK: - Constants

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let maxRetries = 5
    private static let retryBaseDelay: Double = 5
    private static let rateLimitRetryBaseDelay: Double = 5
    private static let activeSessionCheckInterval: TimeInterval = 15
    private static let activeSessionThreshold: TimeInterval = 60
    private static let hysteresisStandard: Double = 5
    private static let hysteresisCustom: Double = 10
    private static let emergencyThreshold: Double = 95
    private static let resetDetectionHigh: Double = 50
    private static let resetDetectionLow: Double = 10
    private static let recentSessionsLimit = 15
    private static let statsWindowDays = 30

    private var rateLimitedUntil: Date?
    private var countdownTimer: AnyCancellable?
    private var autoRefreshTimer: AnyCancellable?
    private var activeSessionTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var isRefreshingToken = false
    private var tokenRefreshQueue: [(Bool) -> Void] = [] // queued callbacks for concurrent refresh requests
    private var statsWorkItem: DispatchWorkItem?
    private var timelineWorkItem: DispatchWorkItem?
    private var roiWorkItem: DispatchWorkItem?

    // Track previous quota utilizations for reset detection
    private var previousQuotaUtilizations: [String: Double] = [:]

    // Multi-threshold notification tracking (persisted)
    private var notifiedThresholds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: UDKey.notifiedThresholds) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: UDKey.notifiedThresholds) }
    }

    // MARK: - Initialisation

    init() {
        let ud = UserDefaults.standard
        let savedInterval = ud.integer(forKey: UDKey.refreshInterval)
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .twoMin
        self.notificationsEnabled = ud.object(forKey: UDKey.notificationsEnabled) as? Bool ?? true
        self.notificationThreshold = ud.object(forKey: UDKey.notificationThreshold) as? Double ?? 20.0
        self.launchAtLogin = ud.bool(forKey: UDKey.launchAtLogin)
        self.compactMode = ud.bool(forKey: UDKey.compactMode)
        let savedDisplayMode = ud.integer(forKey: UDKey.menuBarDisplayMode)
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedDisplayMode) ?? .percentageAndTimer
        self.dailyBudget = ud.double(forKey: UDKey.dailyBudget)

        // Load per-project budgets
        if let data = ud.data(forKey: UDKey.projectBudgets),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.projectBudgets = decoded
        } else {
            self.projectBudgets = [:]
        }

        // Load custom alert rules
        if let data = ud.data(forKey: UDKey.customAlertRules),
           let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) {
            self.customAlertRules = decoded
        } else {
            self.customAlertRules = []
        }

        // Load session annotations
        if let data = ud.data(forKey: UDKey.sessionAnnotations),
           let decoded = try? JSONDecoder().decode([String: SessionAnnotation].self, from: data) {
            self.sessionAnnotations = decoded
        } else {
            self.sessionAnnotations = [:]
        }

        // Load accounts
        if let data = ud.data(forKey: UDKey.accounts),
           let decoded = try? JSONDecoder().decode([AccountInfo].self, from: data) {
            self.accounts = decoded
        } else {
            self.accounts = []
        }
        self.activeAccountIndex = ud.integer(forKey: UDKey.activeAccountIndex)

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
        isGitAvailable = GitAnalyzer.isGitAvailable()

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
            let weekStart = cal.date(byAdding: .day, value: -7, to: now) ?? now
            let monthStart = cal.date(byAdding: .day, value: -Self.statsWindowDays, to: now) ?? now

            // Single pass: analyze + collect recent sessions together
            let result = SessionAnalyzer.analyzeWithSessions(since: monthStart, recentLimit: Self.recentSessionsLimit)
            let month = result.stats
            let week = month.filtered(since: weekStart)
            let today = month.filtered(since: todayStart)

            DispatchQueue.main.async {
                self?.todayStats = today
                self?.weekStats = week
                self?.monthStats = month
                self?.sessionHistory = result.recentSessions
                self?.isLoadingStats = false
                Log.info("Stats: today=$\(String(format: "%.2f", today.totalCost)) week=$\(String(format: "%.2f", week.totalCost)) month=$\(String(format: "%.2f", month.totalCost)) projects=\(month.byProject.count) sessions=\(result.recentSessions.count)")
            }
        }
        statsWorkItem = workItem
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }

    // MARK: - Timeline

    func refreshTimeline() {
        isLoadingTimeline = true
        timelineWorkItem?.cancel()
        let date = timelineDate
        let workItem = DispatchWorkItem { [weak self] in
            let sessions = SessionAnalyzer.timelineSessions(for: date)
            DispatchQueue.main.async {
                self?.timelineSessions = sessions
                self?.isLoadingTimeline = false
            }
        }
        timelineWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    func timelineGoToPreviousDay() {
        timelineDate = Calendar.current.date(byAdding: .day, value: -1, to: timelineDate) ?? timelineDate
        refreshTimeline()
    }

    func timelineGoToNextDay() {
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: timelineDate),
              next <= Date() else { return }
        timelineDate = next
        refreshTimeline()
    }

    // MARK: - ROI

    private static let assistedWindowSeconds: TimeInterval = 2 * 60 * 60 // 2 hours

    func refreshROI() {
        guard isGitAvailable else { return }
        isLoadingROI = true
        roiWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            let stats = Self.computeROI()
            DispatchQueue.main.async {
                self?.roiStats = stats
                self?.isLoadingROI = false
            }
        }
        roiWorkItem = workItem
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }

    private static func computeROI() -> ROIStats {
        let days = 30
        let cal = Calendar.current

        let allCommits = GitAnalyzer.allCommits(sinceDaysAgo: days)
        guard !allCommits.isEmpty else { return .empty }

        // Single-pass: get all sessions for the last 30 days at once
        let since = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let allSessions = SessionAnalyzer.allSessions(since: since)

        // Sort sessions by start time for binary-search-based matching
        let sortedSessions = allSessions.sorted { $0.startTime < $1.startTime }
        let sessionStarts = sortedSessions.map(\.startTime)

        // A commit is assisted if it falls within session.start...session.end+2h for the same project
        let assistedCommits = allCommits.filter { commit in
            // Binary search: find first session that could overlap (startTime <= commit.date)
            // Sessions are sorted by startTime — find rightmost session starting <= commit.date
            var lo = 0, hi = sessionStarts.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if sessionStarts[mid] <= commit.date { lo = mid + 1 } else { hi = mid }
            }
            // Check sessions in a window around the insertion point
            let searchStart = max(0, lo - sortedSessions.count) // check all before (could have long windows)
            let searchEnd = min(sortedSessions.count, lo + 1)
            let commitPathLower = commit.projectPath.lowercased()
            for i in (0..<searchEnd).reversed() {
                let session = sortedSessions[i]
                // Early exit: if session ended+window is before commit, no earlier session can match either
                let windowEnd = session.endTime.addingTimeInterval(assistedWindowSeconds)
                if windowEnd < commit.date { break }
                if commit.date >= session.startTime && commitPathLower.contains(session.projectName.lowercased()) {
                    return true
                }
            }
            return false
        }

        let totalCost = allSessions.reduce(0.0) { $0 + $1.cost }
        let totalLines = assistedCommits.reduce(0) { $0 + $1.totalLinesChanged }
        let costPerCommit = assistedCommits.isEmpty ? 0 : totalCost / Double(assistedCommits.count)
        let costPerLine = totalLines == 0 ? 0 : totalCost / Double(totalLines)

        // By project
        let commitsByProject = Dictionary(grouping: assistedCommits, by: { $0.projectPath })
        let sessionsByProject = Dictionary(grouping: allSessions, by: { $0.projectName.lowercased() })

        let byProject: [ProjectROI] = commitsByProject.map { (path, commits) in
            let projectName = path.split(separator: "/").last.map(String.init) ?? path
            let projectSessions = sessionsByProject.first { path.lowercased().contains($0.key) }?.value ?? []
            let projCost = projectSessions.reduce(0.0) { $0 + $1.cost }
            let projLines = commits.reduce(0) { $0 + $1.totalLinesChanged }

            var modelMap: [String: (cost: Double, count: Int)] = [:]
            for session in projectSessions {
                for msg in session.messages {
                    let model = msg.model.contains("opus") ? "Opus" :
                               msg.model.contains("sonnet") ? "Sonnet" :
                               msg.model.contains("haiku") ? "Haiku" : msg.model
                    let existing = modelMap[model] ?? (cost: 0, count: 0)
                    modelMap[model] = (cost: existing.cost + msg.cost, count: existing.count + 1)
                }
            }
            let totalModelCost = modelMap.values.reduce(0.0) { $0 + $1.cost }
            let breakdown = modelMap.map { (model, data) in
                let proportion = totalModelCost > 0 ? data.cost / totalModelCost : 0
                return (model: model, cost: data.cost, commits: Int(Double(commits.count) * proportion))
            }

            return ProjectROI(
                projectName: projectName,
                totalCost: projCost,
                assistedCommits: commits.count,
                totalLinesChanged: projLines,
                costPerCommit: commits.isEmpty ? 0 : projCost / Double(commits.count),
                costPerLine: projLines == 0 ? 0 : projCost / Double(projLines),
                modelBreakdown: breakdown
            )
        }.sorted { $0.totalCost > $1.totalCost }

        // Daily trend
        let dailyTrend: [(date: Date, cost: Double, commits: Int)] = (0..<days).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let dayStart = cal.startOfDay(for: date)
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let dayCost = allSessions.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
                .reduce(0.0) { $0 + $1.cost }
            let dayCommits = assistedCommits.filter { $0.date >= dayStart && $0.date < dayEnd }.count
            return (date: dayStart, cost: dayCost, commits: dayCommits)
        }.reversed()

        // By model aggregate
        var globalModelMap: [String: (cost: Double, commits: Double)] = [:]
        for proj in byProject {
            for bd in proj.modelBreakdown {
                let existing = globalModelMap[bd.model] ?? (cost: 0, commits: 0)
                globalModelMap[bd.model] = (cost: existing.cost + bd.cost, commits: existing.commits + Double(bd.commits))
            }
        }
        let byModel = globalModelMap.map { (model, data) in
            let avgCPC = data.commits > 0 ? data.cost / data.commits : 0
            return (model: model, cost: data.cost, avgCostPerCommit: avgCPC)
        }.sorted { $0.cost > $1.cost }

        return ROIStats(
            period: days,
            totalCost: totalCost,
            totalAssistedCommits: assistedCommits.count,
            totalLinesChanged: totalLines,
            costPerCommit: costPerCommit,
            costPerLine: costPerLine,
            byProject: byProject,
            dailyTrend: Array(dailyTrend),
            byModel: byModel
        )
    }

    // MARK: - Active session detection

    private func setupActiveSessionDetection() {
        activeSessionTimer = Timer.publish(every: Self.activeSessionCheckInterval, on: .main, in: .common)
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
                    // Use resourceValues from directory listing instead of extra stat() call
                    if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                       let modDate = values.contentModificationDate,
                       now.timeIntervalSince(modDate) < threshold {
                        // Compute cost directly on the found file — no re-scan
                        let sessionData = SessionAnalyzer.sessionCost(for: file)
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
                Log.info("Skipping refresh, rate limited for \(remaining)s more")
                return
            }
            rateLimitedUntil = nil
        }

        if auth.tokenNeedsRefresh && auth.refreshToken != nil {
            isLoading = true
            errorMessage = nil
            if isRefreshingToken {
                // Already refreshing — queue this request to avoid duplicate token refreshes
                tokenRefreshQueue.append { [weak self] success in
                    guard let self else { return }
                    if success { self.fetchUsage() }
                    else {
                        self.isLoading = false
                        self.errorMessage = "Session expired — run `claude login`"
                    }
                }
                return
            }
            isRefreshingToken = true
            auth.refreshAccessToken { [weak self] success in
                guard let self else { return }
                self.isRefreshingToken = false
                let queued = self.tokenRefreshQueue
                self.tokenRefreshQueue.removeAll()
                if success {
                    self.fetchUsage()
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Session expired — run `claude login`"
                    }
                }
                // Notify queued callers
                for callback in queued { callback(success) }
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

        Log.info("Fetching usage from OAuth API... (attempt \(retryCount + 1))")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error = error {
                    if retryCount < Self.maxRetries {
                        let delay = pow(2.0, Double(retryCount))
                        Log.warn("Network error, retrying in \(Int(delay))s: \(error.localizedDescription)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.fetchUsage(retryCount: retryCount + 1)
                        }
                        return
                    }
                    self.isLoading = false
                    self.errorMessage = "Network error — check your connection"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.isLoading = false
                    self.errorMessage = "Invalid response"
                    return
                }

                Log.info("HTTP \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200:
                    guard let data = data else {
                        self.isLoading = false
                        self.errorMessage = "Empty response"
                        return
                    }
                    if let raw = String(data: data, encoding: .utf8) {
                        Log.info("Response: \(raw.prefix(500))")
                    }
                    // Store previous utilizations for reset detection
                    self.previousQuotaUtilizations = Dictionary(
                        uniqueKeysWithValues: self.quotas.map { ($0.label, $0.utilization) }
                    )
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
                        Log.info("Got \(httpResponse.statusCode), attempting token refresh...")
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
                        Log.info("429 with Retry-After:0 — likely stale token, refreshing...")
                        self.auth.refreshAccessToken { success in
                            if success {
                                Log.info("Token refreshed, retrying fetch...")
                                self.fetchUsage(retryCount: retryCount + 1)
                            } else {
                                DispatchQueue.main.async {
                                    self.isLoading = false
                                    self.errorMessage = "Session expired — run `claude login`"
                                }
                            }
                        }
                    } else if !self.quotas.isEmpty {
                        // We have cached data — use Retry-After header if present
                        let cooldown = retryAfterValue > 0 ? retryAfterValue : 30.0
                        self.isLoading = false
                        self.rateLimitedUntil = Date().addingTimeInterval(cooldown)
                        Log.info("Rate limited (429), keeping existing data, retry in \(Int(cooldown))s")
                    } else if retryCount < Self.maxRetries {
                        let delay = 5 * pow(2.0, Double(retryCount))
                        Log.info("Rate limited (429), retrying in \(Int(delay))s (attempt \(retryCount + 1)/\(Self.maxRetries))...")
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
                        Log.warn("Server error \(httpResponse.statusCode), retrying in \(Int(delay))s")
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
        do {
            let response = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
            applyUsageResponse(response)
        } catch {
            Log.error("Failed to parse usage response: \(error)")
            if let raw = String(data: data, encoding: .utf8) {
                Log.info("Raw response: \(raw.prefix(300))")
            }
            errorMessage = "Failed to parse response"
        }
    }

    private func applyUsageResponse(_ response: OAuthUsageResponse) {
        let quotaDefs: [(quota: QuotaData?, label: String, icon: String)] = [
            (response.fiveHour, "Session (5h)", "bolt.fill"),
            (response.sevenDay, "Weekly (all models)", "calendar"),
            (response.sevenDaySonnet, "Sonnet (7d)", "sparkle"),
            (response.sevenDayOpus, "Opus (7d)", "star.fill"),
        ]

        quotas = quotaDefs.compactMap { def in
            guard let q = def.quota else { return nil }
            return UsageQuota(
                label: def.label,
                icon: def.icon,
                utilization: q.utilization,
                resetsAt: q.resetsAt.flatMap(Formatters.parseISO)
            )
        }
        Log.info("Parsed \(quotas.count) quotas")
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
        let thresholds = Array(Set([customThreshold, Self.emergencyThreshold])).sorted()

        // Build pairs of (quota, threshold) that need action
        let pairs = quotas.flatMap { quota in
            thresholds.map { threshold in (quota: quota, threshold: threshold, key: "\(quota.label)-\(Int(threshold))") }
        }

        let toNotify = pairs.filter { $0.quota.utilization >= $0.threshold && !notifiedThresholds.contains($0.key) }
        let toRearm = pairs.filter { $0.quota.utilization < $0.threshold - Self.hysteresisStandard && notifiedThresholds.contains($0.key) }

        // Send notifications
        toNotify.forEach { pair in
            let content = UNMutableNotificationContent()
            content.title = "Claude God"
            content.body = pair.threshold >= Self.emergencyThreshold
                ? "\(pair.quota.label): \(Int(pair.quota.utilization))% used — almost at limit!"
                : "\(pair.quota.label): \(Int(pair.quota.utilization))% used"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "usage-\(UUID().uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }

        // Update thresholds atomically
        notifiedThresholds = notifiedThresholds
            .union(Set(toNotify.map(\.key)))
            .subtracting(Set(toRearm.map(\.key)))
    }

    // MARK: - Reset notifications

    private func checkResetNotifications() {
        guard notificationsEnabled else { return }

        let resetQuotas = quotas.filter { quota in
            guard let previousUtil = previousQuotaUtilizations[quota.label] else { return false }
            return previousUtil > Self.resetDetectionHigh && quota.utilization < Self.resetDetectionLow
        }

        resetQuotas.forEach { quota in
            let content = UNMutableNotificationContent()
            content.title = "Claude God"
            content.body = "\(quota.label) quota reset — you're back to \(Int(quota.utilization))%"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "reset-\(UUID().uuidString)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            Log.info("Reset notification sent for \(quota.label)")
        }
    }

    // MARK: - Custom alert rules check

    private func checkCustomAlerts() {
        guard notificationsEnabled else { return }
        // Collect index changes to apply after iteration (avoid mutating @Published during loop)
        var toNotify: [Int] = []
        var toRearm: [Int] = []
        for i in customAlertRules.indices {
            let rule = customAlertRules[i]
            guard let quota = quotas.first(where: { $0.label == rule.quotaLabel }) else { continue }
            if quota.utilization >= rule.threshold && !rule.notified {
                let content = UNMutableNotificationContent()
                content.title = "Claude God"
                content.body = "\(rule.quotaLabel): \(Int(quota.utilization))% used (alert at \(Int(rule.threshold))%)"
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "custom-alert-\(rule.id.uuidString)",
                    content: content, trigger: nil
                )
                UNUserNotificationCenter.current().add(request)
                toNotify.append(i)
            } else if quota.utilization < rule.threshold - Self.hysteresisCustom && rule.notified {
                toRearm.append(i)
            }
        }
        // Apply mutations once
        for i in toNotify { customAlertRules[i].notified = true }
        for i in toRearm { customAlertRules[i].notified = false }
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
            defaults.set(data, forKey: UDKey.widgetQuotas)
        }
        defaults.set(todayStats.totalCost, forKey: UDKey.widgetTodayCost)
        defaults.set(todayStats.totalMessages, forKey: UDKey.widgetTodayMessages)
        defaults.set(Date().timeIntervalSince1970, forKey: UDKey.widgetLastUpdate)

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
            Log.error("Failed to update launch at login: \(error.localizedDescription)")
        }
    }

    // MARK: - Copy & Export

    func copyStatsToClipboard() -> Bool {
        let fmt: (Double) -> String = { cost in
            cost >= 0.01 ? String(format: "$%.2f", cost) : String(format: "$%.3f", cost)
        }

        let sections: [[String]] = [
            ["Claude God — Usage Stats", ""],
            quotas.isEmpty ? [] : (
                ["── Quotas ──"] +
                quotas.map { "\($0.label): \(Int($0.utilization))% used" } +
                [""]
            ),
            [
                "── Cost (JSONL) ──",
                "Today: \(fmt(todayStats.totalCost)) (\(todayStats.totalMessages) msgs)",
                "7 days: \(fmt(weekStats.totalCost)) (\(weekStats.totalMessages) msgs)",
                "30 days: \(fmt(monthStats.totalCost)) (\(monthStats.totalMessages) msgs)",
            ],
            monthStats.byModel.isEmpty ? [] : (
                ["", "── Models (30d) ──"] +
                monthStats.byModel.map { "\($0.shortName): \(fmt($0.cost))" }
            ),
            monthStats.byProject.isEmpty ? [] : (
                ["", "── Projects (30d) ──"] +
                monthStats.byProject.map { "\($0.projectName): \(fmt($0.totalCost)) (\($0.totalMessages) msgs)" }
            ),
        ]

        let text = sections.flatMap { $0 }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }

    @Published var csvExportSuccess: Bool?
    @Published var jsonExportSuccess: Bool?

    func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "claude-usage-\(Formatters.csvDate.string(from: Date())).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let exportData: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "period": "30 days",
            "totalCost": monthStats.totalCost,
            "totalMessages": monthStats.totalMessages,
            "sessionCount": monthStats.sessionCount,
            "models": monthStats.aggregatedModels.map { [
                "name": $0.shortName,
                "cost": $0.cost,
                "tokens": $0.tokens.totalTokens
            ] },
            "projects": monthStats.byProject.map { [
                "name": $0.projectName,
                "cost": $0.totalCost,
                "messages": $0.totalMessages,
                "sessions": $0.sessionCount
            ] },
            "daily": monthStats.daily.reversed().map { [
                "date": Formatters.csvDate.string(from: $0.date),
                "cost": $0.cost,
                "messages": $0.messageCount
            ] }
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: url, options: .atomic)
            jsonExportSuccess = true
        } catch {
            jsonExportSuccess = false
            Log.error("JSON export failed: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.jsonExportSuccess = nil
        }
    }

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
            Log.error("CSV export failed: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.csvExportSuccess = nil
        }
    }
}
