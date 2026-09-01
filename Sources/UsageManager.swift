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

// MARK: - Popover text size

/// Multiplier applied to every font in the popover. Stored as the raw multiplier
/// so future presets can be added without migrating persisted values.
enum TextScale: Double, CaseIterable, Identifiable {
    case small = 0.9
    case medium = 1.0
    case large = 1.2
    case extraLarge = 1.4

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .extraLarge: return "XL"
        }
    }

    static func nearest(to value: Double) -> TextScale {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .medium
    }
}

// MARK: - Menu bar display mode

enum MenuBarDisplayMode: Int, CaseIterable, Identifiable {
    case iconOnly = 0
    case rings = 5             // Apple Watch-style concentric rings
    case percentage = 1
    case percentageAndTimer = 2
    case allQuotas = 3
    case sessionTimerAndWeek = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .iconOnly: return "Icon"
        case .rings: return "Rings"
        case .percentage: return "Session"
        case .percentageAndTimer: return "Timer"
        case .allQuotas: return "All"
        case .sessionTimerAndWeek: return "Session+Week"
        }
    }

    var description: String {
        switch self {
        case .iconOnly: return "C"
        case .rings: return "◎ activity rings"
        case .percentage: return "C 15%"
        case .percentageAndTimer: return "C 15% · 2h31m"
        case .allQuotas: return "C 15% | 31% | 22%"
        case .sessionTimerAndWeek: return "C 15% · 2h31m | W 31%"
        }
    }

    /// Modes that render a live countdown — drive a 1s tick and the compact timer format
    var showsLiveTimer: Bool {
        self == .percentageAndTimer || self == .sessionTimerAndWeek
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
    /// CLAUDE_CONFIG_DIR of this account; nil = the default ~/.claude login.
    /// Optional so account lists saved by earlier versions still decode.
    var configDir: String? = nil
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
    let sevenDayOmelette: QuotaData?   // Claude Design
    let sevenDayCowork: QuotaData?
    let sevenDayOauthApps: QuotaData?
    let iguanaNecktie: QuotaData?
    let omelettPromotional: QuotaData?
    let extraUsage: ExtraUsageData?
    let limits: [LimitEntry]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayOmelette = "seven_day_omelette"
        case sevenDayCowork = "seven_day_cowork"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case iguanaNecktie = "iguana_necktie"
        case omelettPromotional = "omelette_promotional"
        case extraUsage = "extra_usage"
        case limits
    }
}

/// Entry in the `limits` array — model-scoped quotas (e.g. the Fable weekly
/// limit) only appear here, not as top-level buckets.
private struct LimitEntry: Decodable {
    let kind: String
    let percent: Double?
    let resetsAt: String?
    let scope: LimitScope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
    }
}

private struct LimitScope: Decodable {
    let model: LimitScopeModel?
}

private struct LimitScopeModel: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
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

struct ExtraUsageData: Decodable {
    let isEnabled: Bool
    let monthlyLimit: Double?   // nil = unlimited
    let usedCredits: Double?    // in cents
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case currency
    }

    /// CA$230.40 formatted from 23040 cents
    var usedFormatted: String {
        guard let cents = usedCredits else { return "$0.00" }
        return String(format: "$%.2f", cents / 100.0)
    }

    var limitFormatted: String {
        guard let cents = monthlyLimit else { return "Unlimited" }
        return String(format: "$%.2f", cents / 100.0)
    }

    var utilization: Double? {
        guard let cents = usedCredits, let limit = monthlyLimit, limit > 0 else { return nil }
        return min(cents / limit * 100, 100)
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
    @Published var extraUsage: ExtraUsageData?
    @Published var isLoading = false
    private var loadingStartedAt: Date?
    private var currentFetchTask: URLSessionDataTask?
    private var currentFetchID: UUID?
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
    enum Tab: Int { case usage, analytics, timeline, roi, extensions }
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

    // MARK: - Memory (claude-mem)

    let memoryManager = MemoryManager()
    let pluginManager = PluginManager()
    let superpowersManager = SuperpowersManager()
    let frontendDesignManager = FrontendDesignManager()
    let githubPluginManager = GitHubPluginManager()
    let genericPluginManager = GenericPluginManager()

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

    @Published var textScale: TextScale {
        didSet {
            UserDefaults.standard.set(textScale.rawValue, forKey: UDKey.textScale)
        }
    }

    /// When on, the current usage snapshot is written to `~/.claude-god/usage.json`
    /// after every refresh so external tools (statusline, tmux, dashboards) can read it.
    @Published var exportUsageJSON: Bool {
        didSet {
            UserDefaults.standard.set(exportUsageJSON, forKey: UDKey.exportUsageJSON)
            if exportUsageJSON {
                exportSnapshotIfEnabled()
            } else {
                UsageExporter.removeSnapshot()
            }
        }
    }

    /// True once the user has run the "install statusline helper" flow.
    /// Owned by Settings UI; drives label state ("Installed" vs "Install").
    @Published var statuslineInstalled: Bool {
        didSet {
            UserDefaults.standard.set(statuslineInstalled, forKey: UDKey.statuslineInstalled)
        }
    }

    @Published var autoReconnect: Bool {
        didSet {
            UserDefaults.standard.set(autoReconnect, forKey: UDKey.autoReconnect)
        }
    }
    @Published var isAutoReconnecting = false
    @Published var terminalSession: TerminalSession? = nil
    /// Set to true after auto-reconnect times out so we don't spam Safari tabs.
    /// Cleared when the user manually triggers Sign In or credentials are refreshed.
    private var reconnectExhausted = false

    @Published var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: UDKey.menuBarDisplayMode)
            setupCountdownTimer()
        }
    }

    /// Tints the menu bar icon *and* text by usage level. Off falls back to the system
    /// color, for users who prefer a monochrome menu bar.
    @Published var coloredMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(coloredMenuBar, forKey: UDKey.coloredMenuBar)
        }
    }

    @Published var dailyBudget: Double {
        didSet {
            UserDefaults.standard.set(dailyBudget, forKey: UDKey.dailyBudget)
        }
    }

    // MARK: - Ring stat options (quotas + virtual timer)

    /// Virtual quota: fraction of the 5-hour session window elapsed.
    /// Ring fills as the window progresses toward reset.
    var sessionTimerQuota: UsageQuota? {
        guard let resetDate = nextResetDate else { return nil }
        let window: TimeInterval = 5 * 3600
        let remaining = max(0, resetDate.timeIntervalSinceNow)
        let elapsed = max(0, window - remaining)
        let pct = min(elapsed / window * 100, 100)
        return UsageQuota(label: "Timer", icon: "timer", utilization: pct, resetsAt: resetDate)
    }

    /// Synthesized quota for extra usage when enabled and a monthly limit is set.
    var extraUsageQuota: UsageQuota? {
        guard let extra = extraUsage,
              extra.isEnabled,
              let util = extra.utilization else { return nil }
        return UsageQuota(
            label: "Extra Usage",
            icon: "dollarsign.circle.fill",
            utilization: util,
            resetsAt: nil
        )
    }

    /// Token quotas + extra usage quota. Single source of truth for alerts and ring options.
    var allNotifiableQuotas: [UsageQuota] {
        var result = quotas
        if let e = extraUsageQuota { result.append(e) }
        return result
    }

    /// All selectable ring options: timer (if available) + live API quotas + extra usage.
    var ringQuotaOptions: [UsageQuota] {
        var opts = quotas
        if let t = sessionTimerQuota { opts.insert(t, at: 0) }
        if let e = extraUsageQuota { opts.append(e) }
        return opts
    }

    /// Up to 3 quota labels displayed as concentric rings in Rings mode.
    /// Empty string = ring slot unused.
    @Published var ringStatLabels: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(ringStatLabels) {
                UserDefaults.standard.set(data, forKey: UDKey.ringStatLabels)
            }
        }
    }

    // MARK: - Propriétés calculées

    var primaryQuota: UsageQuota? {
        quotas.first(where: { $0.label.contains("Session") })
            ?? quotas.first
            ?? extraUsageQuota
    }

    /// The quota with the highest utilization (worst state) — includes extra usage.
    private var worstQuota: UsageQuota? {
        allNotifiableQuotas.max(by: { $0.utilization < $1.utilization })
    }

    /// Best representation of the weekly quota: prefer the combined "Weekly (all models)",
    /// otherwise fall back to the worst of Sonnet/Opus 7d so users on the per-model plan still see a value.
    private var weeklyQuota: UsageQuota? {
        if let combined = quotas.first(where: { $0.label.contains("Weekly") }) {
            return combined
        }
        return quotas
            .filter { $0.label.contains("7d") }
            .max(by: { $0.utilization < $1.utilization })
    }

    var menuBarTitle: String {
        switch menuBarDisplayMode {
        case .iconOnly, .rings:
            return ""
        case .percentage:
            guard let q = primaryQuota else { return "—" }
            return "\(Int(q.utilization))%"
        case .percentageAndTimer:
            guard let q = primaryQuota else { return "—" }
            let timer = timeUntilReset == "—" ? "" : " · \(timeUntilReset)"
            return "\(Int(q.utilization))%\(timer)"
        case .allQuotas:
            var parts = quotas.map { "\(Int($0.utilization))%" }
            if let e = extraUsageQuota { parts.append("E \(Int(e.utilization))%") }
            return parts.isEmpty ? "—" : parts.joined(separator: " | ")
        case .sessionTimerAndWeek:
            guard let session = primaryQuota else { return "—" }
            let timer = timeUntilReset == "—" ? "" : " · \(timeUntilReset)"
            let week = weeklyQuota.map { " | W \(Int($0.utilization))%" } ?? ""
            return "\(Int(session.utilization))%\(timer)\(week)"
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

    /// Secondary hint distinguishing warning from critical when the menu bar is monochrome.
    /// With tinting on, the color already carries that signal, so dimming only costs legibility.
    var menuBarIconOpacity: Double {
        guard !coloredMenuBar, let q = worstQuota else { return 1.0 }
        return q.level == .warning ? 0.7 : 1.0
    }

    /// Usage-level tint applied to both the menu bar icon and its text, so the whole
    /// label reads as one status indicator. `.primary` when tinting is off or no quota
    /// has loaded yet — the system color keeps contrast on light and dark menu bars.
    var menuBarTint: Color {
        guard coloredMenuBar, let q = worstQuota else { return .primary }
        return q.level.color
    }

    var nextResetDate: Date? {
        // Use primary quota's reset date (session), falling back to nearest reset across all quotas
        if let primary = primaryQuota?.resetsAt, primary.timeIntervalSinceNow > 0 {
            return primary
        }
        return quotas.compactMap(\.resetsAt)
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
    }

    // MARK: - Peak / Off-peak detection

    /// Peak hours: weekdays 5am–11am US Pacific. Anthropic's throttling window for 5-hour
    /// session limits — overlap of US morning, European afternoon, and Asia evening demand
    /// (announced 2026-03-26: https://x.com/trq212/status/2037254607001559305).
    private static let peakTimezone = TimeZone(identifier: "America/Los_Angeles")!
    private static let peakStartHour = 5
    private static let peakEndHour = 11

    /// Human-readable peak window, derived from `peakStartHour` / `peakEndHour` so tooltips
    /// stay in sync if the policy changes.
    static var peakHoursDescription: String {
        "Mon–Fri \(formatHour(peakStartHour))–\(formatHour(peakEndHour)) PT"
    }

    private static func formatHour(_ hour: Int) -> String {
        let suffix = hour < 12 ? "am" : "pm"
        let display = hour == 0 ? 12 : (hour <= 12 ? hour : hour - 12)
        return "\(display)\(suffix)"
    }

    var isPeakHours: Bool {
        let cal = Calendar.current
        var pacificCal = cal
        pacificCal.timeZone = Self.peakTimezone
        let now = Date()
        let weekday = pacificCal.component(.weekday, from: now)
        let hour = pacificCal.component(.hour, from: now)
        let isWeekday = weekday >= 2 && weekday <= 6 // Mon–Fri
        return isWeekday && hour >= Self.peakStartHour && hour < Self.peakEndHour
    }

    /// Time until next peak/off-peak transition
    var peakTransitionDescription: String {
        let cal = Calendar.current
        var pacificCal = cal
        pacificCal.timeZone = Self.peakTimezone
        let now = Date()

        if isPeakHours {
            // Currently peak → find when off-peak starts (11am PT today)
            var comps = pacificCal.dateComponents([.year, .month, .day], from: now)
            comps.hour = Self.peakEndHour
            comps.minute = 0
            comps.second = 0
            comps.timeZone = Self.peakTimezone
            if let offPeakStart = pacificCal.date(from: comps) {
                let remaining = offPeakStart.timeIntervalSince(now)
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                return hours > 0 ? "Off-peak in \(hours)h\(String(format: "%02d", minutes))m" : "Off-peak in \(minutes)m"
            }
        } else {
            // Currently off-peak → find next peak start
            let weekday = pacificCal.component(.weekday, from: now)
            let hour = pacificCal.component(.hour, from: now)

            var daysUntilPeak = 0
            if weekday >= 2 && weekday <= 6 && hour < Self.peakStartHour {
                // Weekday before peak → peak starts today
                daysUntilPeak = 0
            } else {
                // After peak or weekend → find next weekday
                let currentWeekday = weekday
                if currentWeekday == 7 { // Saturday
                    daysUntilPeak = 2
                } else if currentWeekday == 1 { // Sunday
                    daysUntilPeak = 1
                } else {
                    // Weekday after 11am → next weekday morning
                    daysUntilPeak = currentWeekday == 6 ? 3 : 1 // Friday → Monday, else tomorrow
                }
            }

            var comps = pacificCal.dateComponents([.year, .month, .day], from: now)
            comps.hour = Self.peakStartHour
            comps.minute = 0
            comps.second = 0
            comps.timeZone = Self.peakTimezone
            if let todayPeak = pacificCal.date(from: comps) {
                let nextPeak = pacificCal.date(byAdding: .day, value: daysUntilPeak, to: todayPeak) ?? todayPeak
                let remaining = nextPeak.timeIntervalSince(now)
                if remaining > 0 {
                    let hours = Int(remaining) / 3600
                    let minutes = (Int(remaining) % 3600) / 60
                    if hours >= 24 {
                        let days = hours / 24
                        let h = hours % 24
                        return "Peak in \(days)d \(h)h"
                    }
                    return hours > 0 ? "Peak in \(hours)h\(String(format: "%02d", minutes))m" : "Peak in \(minutes)m"
                }
            }
        }
        return ""
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
    /// Budget for a session recovery round-trip (Keychain read + possible token refresh).
    private static let sessionRecoveryTimeout: TimeInterval = 20
    private static let maxRetries = 5
    private static let retryBaseDelay: Double = 5
    private static let rateLimitRetryBaseDelay: Double = 5
    private static let activeSessionCheckInterval: TimeInterval = 60
    private static let activeSessionThreshold: TimeInterval = 60
    private static let hysteresisStandard: Double = 5
    private static let hysteresisCustom: Double = 10
    private static let emergencyThreshold: Double = 95
    private static let resetDetectionHigh: Double = 50
    private static let resetDetectionLow: Double = 10
    private static let recentSessionsLimit = 15
    private static let statsWindowDays = 30

    private var rateLimitedUntil: Date?
    private var consecutive429Count = 0
    private var countdownTimer: AnyCancellable?
    private var autoRefreshTimer: AnyCancellable?
    private var activeSessionTimer: AnyCancellable?
    private var reconnectPollTimer: AnyCancellable?
    private var expiredCredentialTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
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
        let savedInterval = ud.object(forKey: UDKey.refreshInterval) as? Int
        self.refreshInterval = savedInterval.flatMap(RefreshInterval.init(rawValue:)) ?? .twoMin
        self.notificationsEnabled = ud.object(forKey: UDKey.notificationsEnabled) as? Bool ?? true
        self.notificationThreshold = ud.object(forKey: UDKey.notificationThreshold) as? Double ?? 20.0
        self.launchAtLogin = ud.bool(forKey: UDKey.launchAtLogin)
        self.compactMode = ud.bool(forKey: UDKey.compactMode)
        let savedTextScale = ud.double(forKey: UDKey.textScale)
        self.textScale = savedTextScale > 0 ? TextScale.nearest(to: savedTextScale) : .medium
        self.exportUsageJSON = ud.bool(forKey: UDKey.exportUsageJSON)
        self.statuslineInstalled = ud.bool(forKey: UDKey.statuslineInstalled)
        self.autoReconnect = ud.bool(forKey: UDKey.autoReconnect)
        let savedHeight = ud.double(forKey: UDKey.windowHeight)
        self.windowHeight = savedHeight > 0 ? savedHeight : 650
        let savedDisplayMode = ud.integer(forKey: UDKey.menuBarDisplayMode)
        self.menuBarDisplayMode = MenuBarDisplayMode(rawValue: savedDisplayMode) ?? .percentageAndTimer
        self.coloredMenuBar = ud.object(forKey: UDKey.coloredMenuBar) as? Bool ?? true
        self.dailyBudget = ud.double(forKey: UDKey.dailyBudget)

        // Load ring stat labels for Icon+ mode
        if let data = ud.data(forKey: UDKey.ringStatLabels),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.ringStatLabels = decoded
        } else {
            self.ringStatLabels = ["Session (5h)", "Opus (7d)", "Sonnet (7d)"]
        }

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

        memoryManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        pluginManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        superpowersManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        frontendDesignManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        githubPluginManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        genericPluginManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        // The account context must be in place before the first credential load,
        // or startup would briefly adopt the default account's token.
        applyActiveAccountContext()
        auth.loadCredentials()
        auth.startWatchingCredentials()

        // Auto-connect when credentials appear via file watcher
        auth.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // tokenExpired guard prevents a flicker loop: fetchUsage -> reloadCredentials -> auth republishes -> sink fires again.
                if self.auth.tokenExpired {
                    // Give the silent path first refusal: popping a sign-in terminal
                    // for a session the poller can restore on its own is pure noise.
                    if self.autoReconnect && !self.isAutoReconnecting && !self.reconnectExhausted
                        && !self.auth.canSelfRefresh {
                        self.launchAutoReconnect()
                    }
                    // Poll credentials in the background so a manual `claude auth login`
                    // in any terminal is picked up without the user clicking Sign In.
                    self.startExpiredCredentialPolling()
                    return
                }
                if self.isAuthenticated && !self.isLoading && (self.quotas.isEmpty || self.errorMessage != nil) {
                    self.reconnectExhausted = false   // fresh credentials — allow future auto-reconnects
                    self.showSettings = false
                    self.refresh()
                }
            }
        }.store(in: &cancellables)

        setupCountdownTimer()
        setupAutoRefresh()
        setupActiveSessionDetection()
        setupWakeObserver()
        isGitAvailable = GitAnalyzer.isGitAvailable()

        if notificationsEnabled {
            requestNotificationPermission()
        }

        if isAuthenticated {
            // Delay first API call to avoid racing with Claude Code on startup
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.refresh()
            }
        }

        refreshStats()
        checkForUpdates()
    }

    // MARK: - Session stats (single-pass optimization)

    /// Tracks the last successful stats refresh so refreshStatsIfStale can skip
    /// scanning JSONL files when the user re-opens the popover seconds apart.
    private var lastStatsRefresh: Date?

    /// Run the stats scan only when the data on screen would actually be out of date.
    /// Called on popover appear so the heavy JSONL scan stays off the auto-refresh
    /// timer (which used to fan it out every 2 min, even with the popover closed).
    func refreshStatsIfStale() {
        let staleThreshold: TimeInterval = 120
        if let last = lastStatsRefresh, Date().timeIntervalSince(last) < staleThreshold { return }
        refreshStats()
    }

    /// Replace the stats on screen with the active account's, pre-empting any
    /// scan already running: `refreshStats` drops the request while one is in
    /// flight, which on an account switch would leave the previous account's
    /// numbers on screen until the next popover open.
    private func forceRefreshStats() {
        statsWorkItem?.cancel()
        statsWorkItem = nil
        isLoadingStats = false
        lastStatsRefresh = nil
        refreshStats()
    }

    func refreshStats() {
        guard !isLoadingStats else { return }
        isLoadingStats = true

        // Cancel any previous in-flight stats work
        statsWorkItem?.cancel()

        // Which account this scan reads; results from a superseded account are
        // discarded rather than allowed to overwrite the new selection's.
        let scannedAccount = ActiveAccount.configDir

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
                guard ActiveAccount.configDir == scannedAccount else { return }
                self?.todayStats = today
                self?.weekStats = week
                self?.monthStats = month
                self?.sessionHistory = result.recentSessions
                self?.isLoadingStats = false
                self?.lastStatsRefresh = Date()
                self?.exportSnapshotIfEnabled()
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
        let scannedAccount = ActiveAccount.configDir
        let workItem = DispatchWorkItem { [weak self] in
            let sessions = SessionAnalyzer.timelineSessions(for: date)
            DispatchQueue.main.async {
                guard ActiveAccount.configDir == scannedAccount else { return }
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

    // MARK: - Auto-reconnect

    /// Runs `claude auth login` in an embedded PTY inside the popover.
    /// The browser OAuth flow still opens automatically. Once credentials appear
    /// in Keychain, the polling loop picks them up and resumes normal operation.
    func launchAutoReconnect() {
        guard !isAutoReconnecting else { return }
        isAutoReconnecting = true
        reconnectExhausted = false   // manual trigger always allowed
        errorMessage = nil
        Log.info("Auto-reconnect: starting embedded terminal session")

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.local/share/fnm/aliases/default/bin/claude",
            "/usr/bin/claude"
        ]
        var claudePath = candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0) })

        if claudePath == nil {
            // Fallback: ask the user's login shell where claude lives
            claudePath = Self.resolveClaudeBinaryViaShell()
        }

        guard let claudePath else {
            Log.warn("claude binary not found — cannot auto-reconnect")
            isAutoReconnecting = false
            errorMessage = "Claude CLI not found. Install it with `npm i -g @anthropic-ai/claude-code`, then run `claude auth login` in Terminal."
            return
        }

        let session = TerminalSession()
        terminalSession = session
        session.start(executablePath: claudePath, args: ["auth", "login"])
        Log.info("Embedded terminal started — polling Keychain every 5s for new credentials")
        startReconnectPolling()
    }

    private func finishReconnect() {
        terminalSession?.stop()
        terminalSession = nil
        isAutoReconnecting = false
    }

    /// Resolve the `claude` binary by running `which claude` in the user's login shell.
    /// Covers nvm, fnm, volta, pnpm global, and other non-standard install locations.
    private static func resolveClaudeBinaryViaShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-c", "which claude"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return nil
        }
        guard p.terminationStatus == 0 else { return nil }
        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: raw, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    /// Poll credentials every 10 seconds when the token is expired but no reconnect flow is running.
    /// This picks up tokens written by a manual `claude auth login` in any terminal.
    private func startExpiredCredentialPolling() {
        expiredCredentialTimer?.cancel()
        expiredCredentialTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.auth.tokenExpired, !self.isAutoReconnecting else {
                    self.expiredCredentialTimer?.cancel()
                    self.expiredCredentialTimer = nil
                    return
                }
                self.auth.recoverSession { [weak self] recovered in
                    guard let self else { return }
                    guard recovered, !self.auth.tokenExpired else {
                        // Silent recovery is out of options — fall back to asking
                        // the user to sign in, if they opted into auto-reconnect.
                        if self.autoReconnect && !self.isAutoReconnecting
                            && !self.reconnectExhausted && !self.auth.canSelfRefresh {
                            self.launchAutoReconnect()
                        }
                        return
                    }
                    Log.info("Expired credential poller: session recovered, resuming")
                    self.expiredCredentialTimer?.cancel()
                    self.expiredCredentialTimer = nil
                    self.reconnectExhausted = false
                    self.errorMessage = nil
                    self.refresh()
                }
            }
    }

    private func startReconnectPolling() {
        reconnectPollTimer?.cancel()
        var elapsed = 0
        reconnectPollTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isAutoReconnecting else { return }
                elapsed += 5
                self.auth.reloadCredentials { [weak self] _ in
                    guard let self else { return }
                    if !self.auth.tokenExpired {
                        Log.info("Auto-reconnect: fresh credentials detected after \(elapsed)s, resuming")
                        self.reconnectPollTimer?.cancel()
                        self.reconnectPollTimer = nil
                        self.reconnectExhausted = false
                        self.finishReconnect()
                        self.refresh()
                    } else if elapsed >= 120 {
                        Log.warn("Auto-reconnect: timed out (120s) waiting for credentials")
                        self.reconnectPollTimer?.cancel()
                        self.reconnectPollTimer = nil
                        self.finishReconnect()
                        self.reconnectExhausted = true   // stop the tab-spam loop
                        self.errorMessage = "Session expired — run `claude auth login` in Terminal"
                    }
                }
            }
    }

    // MARK: - Actions

    /// Manual refresh — always clears rate limit cooldown
    func refresh() {
        rateLimitedUntil = nil
        consecutive429Count = 0
        refreshInternal()
    }

    /// Refresh if data is older than 2 minutes (called on popover appear)
    func refreshIfStale() {
        let staleThreshold: TimeInterval = 120
        if let last = lastRefresh, Date().timeIntervalSince(last) < staleThreshold { return }
        Log.info("Data stale (>2min) — auto-refreshing on popover open")
        refresh()
    }

    /// Auto-refresh — respects rate limit cooldown
    func autoRefresh() {
        if let until = rateLimitedUntil, Date() < until {
            let remaining = Int(until.timeIntervalSince(Date()))
            if remaining > 0 {
                Log.info("Auto-refresh skipped, rate limited for \(remaining)s more")
                return
            }
            rateLimitedUntil = nil
            consecutive429Count = 0
            Log.info("Rate limit cooldown expired, resetting backoff")
        }
        refreshInternal()
    }

    private func refreshInternal() {
        // Safety: if isLoading has been stuck for >30s, cancel in-flight fetch and reset.
        // Must stay above sessionRecoveryTimeout so a legitimate recovery isn't killed.
        if isLoading, let started = loadingStartedAt, Date().timeIntervalSince(started) > 30 {
            Log.warn("isLoading stuck for >30s — cancelling fetch and resetting")
            currentFetchTask?.cancel()
            finishLoading()
        }
        guard !isLoading else { return }
        guard isAuthenticated, auth.accessToken != nil else {
            errorMessage = "Not authenticated — run `claude auth login` in Terminal"
            return
        }

        // Never *proactively* refresh the OAuth token — it is single-use and shared
        // with the Claude Code CLI, so consuming it early invalidates the CLI's
        // in-memory copy and forces the user to /login (see issue #40). Recovery is
        // reactive only: fetchUsage calls auth.recoverSession, which reloads from
        // disk/Keychain and refreshes solely when the token has been dead so long
        // that no CLI can still be holding it.
        isLoading = true
        loadingStartedAt = Date()
        errorMessage = nil
        fetchUsage()
    }

    // MARK: - Fetch with retry

    private func fetchUsage(retryCount: Int = 0) {
        guard let token = auth.accessToken else {
            finishLoading(error: "No access token — run `claude auth login`")
            return
        }

        if auth.tokenExpired {
            Log.warn("Token expired, attempting to recover the session...")
            var didComplete = false
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, !didComplete else { return }
                didComplete = true
                Log.warn("Session recovery timed out after \(Int(Self.sessionRecoveryTimeout))s")
                self.finishLoading(error: "Session expired — run `claude auth login`")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.sessionRecoveryTimeout, execute: timeout)
            auth.recoverSession { [weak self] success in
                timeout.cancel()
                guard let self, !didComplete else { return }
                didComplete = true
                if success && !self.auth.tokenExpired {
                    Log.info("Got fresh token, fetching usage...")
                    self.fetchUsage(retryCount: retryCount)
                } else {
                    self.finishLoading(error: "Session expired — run `claude auth login`")
                }
            }
            return
        }

        // Tag this fetch so stale responses from cancelled/superseded fetches are ignored
        if retryCount == 0 {
            currentFetchTask?.cancel()
            let newID = UUID()
            currentFetchID = newID
        }
        let activeFetchID = currentFetchID!

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeGod", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        Log.info("Fetching usage from OAuth API... (attempt \(retryCount + 1), id: \(activeFetchID.uuidString.prefix(8)))")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Ignore response if a newer fetch has been started
                guard self.currentFetchID == activeFetchID else {
                    Log.info("Ignoring stale fetch response (id: \(activeFetchID.uuidString.prefix(8)))")
                    return
                }

                if let error = error {
                    // Don't retry if cancelled — but clear loading state
                    if (error as NSError).code == NSURLErrorCancelled {
                        Log.info("Fetch cancelled")
                        self.finishLoading()
                        return
                    }
                    if retryCount < Self.maxRetries {
                        let delay = pow(2.0, Double(retryCount))
                        Log.warn("Network error, retrying in \(Int(delay))s: \(error.localizedDescription)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            self?.fetchUsage(retryCount: retryCount + 1)
                        }
                        return
                    }
                    self.finishLoading(error: "Network error — check your connection")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.finishLoading(error: "Invalid response")
                    return
                }

                Log.info("HTTP \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200:
                    guard let data = data else {
                        self.finishLoading(error: "Empty response")
                        return
                    }
                    if let raw = String(data: data, encoding: .utf8) {
                        Log.info("Response: \(raw)")
                        self.lastRawAPIResponse = raw
                    }
                    self.previousQuotaUtilizations = Dictionary(
                        uniqueKeysWithValues: self.quotas.map { ($0.label, $0.utilization) }
                    )
                    self.parseUsageResponse(data)
                    self.finishLoading()
                    self.consecutive429Count = 0
                    self.lastRefresh = Date()
                    // Stats refresh is deferred to popover-open (refreshStatsIfStale)
                    // so the 30-day JSONL scan doesn't run on every background fetch.
                    self.checkNotifications()
                    self.checkResetNotifications()
                    self.checkCustomAlerts()
                    self.checkProjectBudgets()
                    self.updateWidgetData()

                case 401, 403:
                    if retryCount == 0 {
                        Log.info("Got \(httpResponse.statusCode), attempting session recovery...")
                        self.auth.recoverSession { [weak self] success in
                            guard let self else { return }
                            if success {
                                self.fetchUsage(retryCount: retryCount + 1)
                            } else {
                                self.finishLoading(error: "Session expired — run `claude auth login`")
                            }
                        }
                    } else {
                        self.finishLoading(error: "Session expired — run `claude auth login`")
                    }

                case 429:
                    let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let retryAfterValue = retryAfterHeader.flatMap(Double.init) ?? -1

                    // A 429 on a token we already know is expired — or one answered
                    // with Retry-After: 0 — is an authentication artifact, not a quota
                    // limit. Recover the session instead of starting a cooldown and
                    // telling the user to wait for a limit that was never hit.
                    let looksLikeStaleToken = self.auth.tokenExpired || retryAfterValue <= 0
                    if looksLikeStaleToken && retryCount == 0 {
                        Log.info("429 (Retry-After:\(Int(retryAfterValue)), expired:\(self.auth.tokenExpired)) — recovering session...")
                        self.auth.recoverSession { [weak self] success in
                            guard let self else { return }
                            if success {
                                Log.info("Session recovered, retrying fetch...")
                                self.fetchUsage(retryCount: retryCount + 1)
                            } else {
                                self.finishLoading(error: "Session expired — run `claude auth login`")
                            }
                        }
                        return
                    }

                    // Recovery already ran and the token is still dead: report the real
                    // problem rather than an imaginary rate limit.
                    if self.auth.tokenExpired {
                        self.finishLoading(error: "Session expired — run `claude auth login`")
                        return
                    }

                    self.consecutive429Count += 1
                    // Server provided a real Retry-After: respect it (capped at 2h)
                    let cooldown: Double
                    if retryAfterValue > 0 {
                        cooldown = min(retryAfterValue, 7200)
                    } else {
                        // No Retry-After header — use moderate backoff
                        let steps: [Double] = [15, 30, 60, 120, 300, 600]
                        let index = min(self.consecutive429Count - 1, steps.count - 1)
                        cooldown = steps[index]
                    }
                    self.rateLimitedUntil = Date().addingTimeInterval(cooldown)
                    if !self.quotas.isEmpty {
                        self.finishLoading()
                        Log.info("Rate limited (429), keeping existing data, retry in \(Int(cooldown))s")
                    } else {
                        let display = cooldown >= 60 ? "\(Int(cooldown / 60))min" : "\(Int(cooldown))s"
                        self.finishLoading(error: "Rate limited — retrying in \(display)")
                        Log.info("Rate limited (429 #\(self.consecutive429Count)), no data yet, will auto-retry in \(Int(cooldown))s")
                    }

                default:
                    if httpResponse.statusCode >= 500 && retryCount < Self.maxRetries {
                        let delay = pow(2.0, Double(retryCount))
                        Log.warn("Server error \(httpResponse.statusCode), retrying in \(Int(delay))s")
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            self?.fetchUsage(retryCount: retryCount + 1)
                        }
                        return
                    }
                    self.finishLoading(error: "Error \(httpResponse.statusCode)")
                }
            }
        }
        currentFetchTask = task
        task.resume()
    }

    /// Centralized loading state reset — guarantees isLoading is always cleared
    private func finishLoading(error: String? = nil) {
        isLoading = false
        loadingStartedAt = nil
        errorMessage = error
        if let error, (error.contains("expired") || error.contains("login") || error.contains("authenticated")) {
            startExpiredCredentialPolling()
        }
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
            (response.fiveHour,          "Session (5h)",        "bolt.fill"),
            (response.sevenDay,          "Weekly (all)",        "calendar"),
            (response.sevenDaySonnet,    "Sonnet (7d)",         "sparkle"),
            (response.sevenDayOpus,      "Opus (7d)",           "star.fill"),
            (response.sevenDayOmelette,  "Claude Design (7d)",  "paintbrush.fill"),
            (response.sevenDayCowork,    "Cowork (7d)",         "person.2.fill"),
            (response.sevenDayOauthApps, "OAuth Apps (7d)",     "app.connected.to.app.below.fill"),
            (response.iguanaNecktie,     "Extended (7d)",       "sparkles"),
            (response.omelettPromotional,"Design Promo (7d)",   "gift.fill"),
        ]

        let scopedWeeklyQuotas = (response.limits ?? [])
            .filter { $0.kind == "weekly_scoped" }
            .compactMap { entry -> UsageQuota? in
                guard let name = entry.scope?.model?.displayName,
                      let percent = entry.percent else { return nil }
                return UsageQuota(
                    label: "Weekly (\(name))",
                    icon: "book.fill",
                    utilization: percent,
                    resetsAt: entry.resetsAt.flatMap(Formatters.parseISO)
                )
            }

        quotas = quotaDefs.compactMap { def in
            guard let q = def.quota else { return nil }
            return UsageQuota(
                label: def.label,
                icon: def.icon,
                utilization: q.utilization,
                resetsAt: q.resetsAt.flatMap(Formatters.parseISO)
            )
        } + scopedWeeklyQuotas
        extraUsage = response.extraUsage
        Log.info("Parsed \(quotas.count) quotas, extraUsage=\(response.extraUsage != nil)")
        exportSnapshotIfEnabled()
    }

    /// Write the current usage snapshot to `~/.claude-god/usage.json` when the
    /// user has opted into the export. No-op otherwise. Called after every
    /// successful OAuth refresh and after JSONL stats reload so external
    /// consumers (statusline, tmux) see the freshest numbers.
    func exportSnapshotIfEnabled() {
        guard exportUsageJSON else { return }
        guard !quotas.isEmpty else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        guard let data = UsageExporter.makeSnapshot(
            version: version,
            quotas: quotas,
            extraUsage: extraUsage,
            activeSessionRunning: isSessionActive,
            activeSessionCost: activeSessionCost,
            activeSessionMessages: activeSessionMessages,
            today: todayStats,
            month: monthStats,
            monthlyForecast: monthlyForecast,
            credentialSource: credentialSource.rawValue
        ) else { return }
        DispatchQueue.global(qos: .utility).async {
            UsageExporter.writeSnapshot(data)
        }
    }

    // MARK: - Countdown

    /// Tracks the active interval so updateCountdown can detect when the
    /// timer needs to be re-armed at a different cadence.
    private var currentCountdownInterval: TimeInterval = 0

    /// 1s ticks only when the menubar shows seconds (live-timer mode AND remaining ≤ 1h).
    /// Above 1h the displayed string only has minute precision, so 60s is enough.
    /// Modes that don't show the timer in the menubar fall back to 60s — `timeUntilReset`
    /// is only consumed inside the popover, which doesn't need finer granularity.
    private func desiredCountdownInterval() -> TimeInterval {
        guard menuBarDisplayMode.showsLiveTimer else { return 60 }
        guard let reset = nextResetDate else { return 60 }
        return reset.timeIntervalSinceNow <= 3600 ? 1 : 60
    }

    private func setupCountdownTimer() {
        countdownTimer?.cancel()
        let interval = desiredCountdownInterval()
        currentCountdownInterval = interval
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
        // Re-arm the timer if we've crossed the 1h threshold (or back) so we don't
        // keep ticking at 1Hz for hours, or stay at 60s through the final minute.
        if desiredCountdownInterval() != currentCountdownInterval {
            setupCountdownTimer()
        }
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let newValue: String
        if menuBarDisplayMode.showsLiveTimer {
            // Keep menu bar compact
            if days > 0 {
                newValue = "\(days)d\(String(format: "%02d", hours))h"
            } else if hours > 0 {
                newValue = "\(hours)h\(String(format: "%02d", minutes))m"
            } else {
                let seconds = Int(remaining) % 60
                newValue = "\(minutes)m\(String(format: "%02d", seconds))s"
            }
        } else {
            if days > 0 {
                newValue = "\(days)d \(hours)h"
            } else if hours > 0 {
                newValue = "\(hours)h \(minutes)m"
            } else {
                newValue = "\(minutes)m"
            }
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
            self?.autoRefresh()
        }
    }

    // MARK: - Wake observer

    private func setupWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Log.info("System wake detected — refreshing timers and data")
            // Cancel any in-flight fetch and reset loading state
            self.currentFetchTask?.cancel()
            self.finishLoading()
            // Recreate timers (they may have drifted or died during sleep)
            self.setupCountdownTimer()
            self.setupAutoRefresh()
            self.setupActiveSessionDetection()
            // Refresh data
            self.refresh()
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
        let pairs = allNotifiableQuotas.flatMap { quota in
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
            guard let quota = allNotifiableQuotas.first(where: { $0.label == rule.quotaLabel }) else { continue }
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

    /// Point every account-scoped subsystem — credentials file, Keychain
    /// service, session analytics, file watcher — at the selected account's
    /// config dir. Must run before any credential load that should honor the
    /// selection.
    private func applyActiveAccountContext() {
        let account = (activeAccountIndex >= 0 && activeAccountIndex < accounts.count)
            ? accounts[activeAccountIndex] : nil
        ActiveAccount.configDir = account?.configDir
        auth.startWatchingCredentials()
    }

    /// `~/.claude` — where Claude Code stores the login used when
    /// CLAUDE_CONFIG_DIR is unset.
    private static var defaultConfigDirPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude").standardizedFileURL.path
    }

    /// The row standing for the default login, so there is always a way back.
    private static var defaultAccount: AccountInfo {
        AccountInfo(
            label: "Default",
            credentialsPath: defaultConfigDirPath + "/.credentials.json",
            configDir: nil
        )
    }

    /// Register the account living in `configDirURL` (a CLAUDE_CONFIG_DIR).
    /// The first added account also inserts a row for the default ~/.claude
    /// login, so there is always a way to switch back to it.
    func addAccount(configDirURL: URL) {
        // The Keychain service name hashes the exact directory string, so store
        // the path in its canonical no-trailing-slash form.
        let dir = configDirURL.standardizedFileURL.path
        // Picking ~/.claude is the default login, not a CLAUDE_CONFIG_DIR
        // profile: its credentials live in the un-suffixed Keychain service, so
        // hashing that path would point the account at an item that never
        // exists and the row could never authenticate.
        let configDir: String? = dir == Self.defaultConfigDirPath ? nil : dir

        if accounts.isEmpty {
            accounts.append(Self.defaultAccount)
        }
        guard !accounts.contains(where: { $0.configDir == configDir }) else { return }
        accounts.append(AccountInfo(
            label: configDirURL.lastPathComponent,
            credentialsPath: dir + "/.credentials.json",
            configDir: configDir
        ))
    }

    /// Re-point every account-scoped subsystem at the current selection, then
    /// reload everything that was derived from the account we just left: quota,
    /// stats and timeline all outlive the switch otherwise.
    private func reloadForActiveAccount() {
        applyActiveAccountContext()
        auth.resetForAccountSwitch()
        // The quota fetch needs a token, and resolving one may go to the
        // Keychain off the main thread — so it waits for the resolution instead
        // of firing against the cleared state.
        auth.reloadCredentials { [weak self] resolved in
            guard let self else { return }
            if resolved {
                // Don't clear quotas — keep old data until new ones arrive
                self.refresh()
            } else {
                self.errorMessage = "No credentials for this account — run `claude auth login` with its CLAUDE_CONFIG_DIR"
            }
        }
        // Transcripts are read straight off disk, so these need no credentials.
        forceRefreshStats()
        refreshTimeline()
    }

    func switchAccount(index: Int) {
        guard index >= 0 && index < accounts.count else { return }
        activeAccountIndex = index
        reloadForActiveAccount()
    }

    func removeAccount(at index: Int) {
        guard index >= 0 && index < accounts.count else { return }
        let previousConfigDir = ActiveAccount.configDir
        accounts.remove(at: index)
        // Removing a row above the active one shifts the selection down with it;
        // without this, deleting an account silently switches to its neighbour.
        if index < activeAccountIndex { activeAccountIndex -= 1 }
        if activeAccountIndex >= accounts.count {
            activeAccountIndex = max(0, accounts.count - 1)
        }
        applyActiveAccountContext()
        // Only pay for a full reload when the removal actually changed which
        // account is active.
        if ActiveAccount.configDir != previousConfigDir {
            reloadForActiveAccount()
        }
    }

    // MARK: - Widget data sharing

    private var lastWidgetQuotaHash: Int = 0

    private func updateWidgetData() {
        // Skip widget update if quotas haven't changed
        let currentHash = quotas.map { "\($0.label):\(Int($0.utilization))" }.joined().hashValue
        guard currentHash != lastWidgetQuotaHash else { return }
        lastWidgetQuotaHash = currentHash

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
    @Published var lastRawAPIResponse: String?

    // MARK: - Window height preference

    @Published var windowHeight: Double {
        didSet { UserDefaults.standard.set(windowHeight, forKey: UDKey.windowHeight) }
    }

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
