// UsageManager.swift
// Gère la logique : appels OAuth API, stockage des données, calculs, notifications

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

    /// utilization = pourcentage UTILISÉ (0-100)
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
    let utilization: Double      // 0-100, pourcentage UTILISÉ
    let resetsAt: Date?

    var level: UsageLevel { UsageLevel(utilization: utilization) }
}

// MARK: - Credential source

enum CredentialSource: String {
    case file = "credentials.json"
    case keychain = "Keychain"
    case environment = "CLAUDE_CODE_OAUTH_TOKEN"
    case none = "Not found"
}

// MARK: - Formatters statiques

enum Formatters {
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

    static func parseISO(_ string: String) -> Date? {
        resetDate.date(from: string) ?? resetDateNoFrac.date(from: string)
    }
}

// MARK: - Manager principal

class UsageManager: ObservableObject {

    // MARK: - Données d'utilisation (nouveau modèle OAuth)

    @Published var quotas: [UsageQuota] = []
    @Published var subscriptionType: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefresh: Date?
    @Published var timeUntilReset: String = "—"
    @Published var isAuthenticated = false

    // MARK: - Session stats (ccusage)

    @Published var todayStats = UsageStats()
    @Published var weekStats = UsageStats()
    @Published var monthStats = UsageStats()
    @Published var showStats = false

    // MARK: - État de l'interface

    @Published var credentialSource: CredentialSource = .none
    @Published var showSettings = false

    // MARK: - Mise à jour

    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var downloadURL: URL?

    static let currentVersion: String = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "1.0.0"

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

    /// Toujours afficher le quota session (5h) dans la menu bar
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

    /// Le prochain reset parmi tous les quotas
    var nextResetDate: Date? {
        quotas.compactMap(\.resetsAt)
            .filter { $0.timeIntervalSinceNow > 0 }
            .min()
    }

    // MARK: - OAuth credentials

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Double?

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scopes = "user:profile user:inference user:sessions:claude_code"

    // MARK: - Timers

    private var countdownTimer: AnyCancellable?
    private var autoRefreshTimer: AnyCancellable?
    private var hasNotifiedLowUsage = false
    private let autoRefreshCooldown: TimeInterval = 30

    // MARK: - Initialisation

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .twoMin
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.notificationThreshold = UserDefaults.standard.object(forKey: "notificationThreshold") as? Double ?? 20.0
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.compactMode = UserDefaults.standard.bool(forKey: "compactMode")

        loadCredentials()

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

    // MARK: - Credential loading

    func loadCredentials() {
        // 1. Fichier ~/.claude/.credentials.json
        let filePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")

        if let data = try? Data(contentsOf: filePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            accessToken = token
            refreshToken = oauth["refreshToken"] as? String
            tokenExpiresAt = oauth["expiresAt"] as? Double
            subscriptionType = oauth["subscriptionType"] as? String ?? ""
            credentialSource = .file
            isAuthenticated = true
            print("[ClaudeGod] Credentials loaded from file (type: \(subscriptionType))")
            return
        }

        // 2. Keychain (service "Claude Code-credentials")
        if let keychainJSON = loadFromKeychain(),
           let oauth = keychainJSON["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            accessToken = token
            refreshToken = oauth["refreshToken"] as? String
            tokenExpiresAt = oauth["expiresAt"] as? Double
            subscriptionType = oauth["subscriptionType"] as? String ?? ""
            credentialSource = .keychain
            isAuthenticated = true
            print("[ClaudeGod] Credentials loaded from Keychain (type: \(subscriptionType))")
            return
        }

        // 3. Variable d'environnement
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            accessToken = envToken
            credentialSource = .environment
            isAuthenticated = true
            print("[ClaudeGod] Credentials loaded from environment")
            return
        }

        credentialSource = .none
        isAuthenticated = false
        print("[ClaudeGod] No credentials found")
    }

    private func loadFromKeychain() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonString = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !jsonString.isEmpty,
                  let jsonData = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { return nil }

            return json
        } catch {
            return nil
        }
    }

    // MARK: - Token refresh

    private var tokenNeedsRefresh: Bool {
        guard let expiresAt = tokenExpiresAt else { return true }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let bufferMs: Double = 5 * 60 * 1000
        return nowMs + bufferMs >= expiresAt
    }

    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let rt = refreshToken else {
            completion(false)
            return
        }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": rt,
            "client_id": Self.clientID,
            "scope": Self.scopes
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("[ClaudeGod] Refreshing OAuth token...")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data = data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode >= 200, httpResponse.statusCode < 300,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["access_token"] as? String, !newToken.isEmpty
            else {
                print("[ClaudeGod] Token refresh failed")
                DispatchQueue.main.async {
                    self?.isAuthenticated = false
                    self?.errorMessage = "Session expired — run `claude login` in Terminal"
                }
                completion(false)
                return
            }

            DispatchQueue.main.async {
                self.accessToken = newToken
                if let newRefresh = json["refresh_token"] as? String {
                    self.refreshToken = newRefresh
                }
                if let expiresIn = json["expires_in"] as? Int {
                    self.tokenExpiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn) * 1000
                }
                print("[ClaudeGod] Token refreshed successfully")
                completion(true)
            }
        }.resume()
    }

    // MARK: - Actions

    func refresh() {
        guard !isLoading else { return }
        guard isAuthenticated, let token = accessToken else {
            errorMessage = "Not authenticated — run `claude login` in Terminal"
            return
        }

        // Refresh token si nécessaire
        if tokenNeedsRefresh && refreshToken != nil {
            isLoading = true
            errorMessage = nil
            refreshAccessToken { [weak self] success in
                guard let self else { return }
                if success {
                    self.fetchUsage()
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                    }
                }
            }
            return
        }

        isLoading = true
        errorMessage = nil
        fetchUsage()
    }

    private func fetchUsage() {
        guard let token = accessToken else { return }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeGod", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        print("[ClaudeGod] Fetching usage from OAuth API...")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    print("[ClaudeGod] Network error: \(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    return
                }

                print("[ClaudeGod] HTTP \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200:
                    guard let data = data else {
                        self.errorMessage = "Empty response"
                        return
                    }
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[ClaudeGod] Response: \(raw.prefix(500))")
                    }
                    self.parseUsageResponse(data)
                    self.lastRefresh = Date()
                    self.refreshStats()
                    self.checkLowUsageNotification()

                case 401, 403:
                    // Token expiré ou invalide, essayer de refresh
                    if self.refreshToken != nil {
                        print("[ClaudeGod] Got \(httpResponse.statusCode), attempting token refresh...")
                        self.isLoading = true
                        self.refreshAccessToken { success in
                            if success {
                                self.fetchUsage()
                            } else {
                                DispatchQueue.main.async {
                                    self.isLoading = false
                                    self.isAuthenticated = false
                                    self.errorMessage = "Session expired — run `claude login`"
                                }
                            }
                        }
                    } else {
                        self.isAuthenticated = false
                        self.errorMessage = "Session expired — run `claude login`"
                    }

                case 429:
                    // Don't overwrite existing data — keep showing last valid quotas
                    if !self.quotas.isEmpty {
                        // Silently ignore, data is still valid
                        print("[ClaudeGod] Rate limited (429), keeping existing data")
                    } else {
                        self.errorMessage = "Rate limited — Claude Code may be active"
                    }

                default:
                    self.errorMessage = "Error \(httpResponse.statusCode)"
                    print("[ClaudeGod] Error \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }

    // MARK: - Response parsing

    private func parseUsageResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "Failed to parse response"
            return
        }

        var newQuotas: [UsageQuota] = []

        // Session (5 heures)
        if let fiveHour = json["five_hour"] as? [String: Any],
           let utilization = fiveHour["utilization"] as? Double {
            let resetsAt = (fiveHour["resets_at"] as? String).flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Session (5h)",
                icon: "bolt.fill",
                utilization: utilization,
                resetsAt: resetsAt
            ))
        }

        // Hebdomadaire (7 jours)
        if let sevenDay = json["seven_day"] as? [String: Any],
           let utilization = sevenDay["utilization"] as? Double {
            let resetsAt = (sevenDay["resets_at"] as? String).flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Weekly (all models)",
                icon: "calendar",
                utilization: utilization,
                resetsAt: resetsAt
            ))
        }

        // Sonnet spécifique
        if let sonnet = json["seven_day_sonnet"] as? [String: Any],
           let utilization = sonnet["utilization"] as? Double {
            let resetsAt = (sonnet["resets_at"] as? String).flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Sonnet (7d)",
                icon: "sparkle",
                utilization: utilization,
                resetsAt: resetsAt
            ))
        }

        // Opus spécifique
        if let opus = json["seven_day_opus"] as? [String: Any],
           let utilization = opus["utilization"] as? Double {
            let resetsAt = (opus["resets_at"] as? String).flatMap(Formatters.parseISO)
            newQuotas.append(UsageQuota(
                label: "Opus (7d)",
                icon: "star.fill",
                utilization: utilization,
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

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkLowUsageNotification() {
        guard notificationsEnabled, let primary = primaryQuota else { return }
        let threshold = 100 - notificationThreshold  // notificationThreshold is "remaining %", convert to utilization
        guard primary.utilization >= threshold else {
            hasNotifiedLowUsage = false
            return
        }
        guard !hasNotifiedLowUsage else { return }

        hasNotifiedLowUsage = true

        let content = UNMutableNotificationContent()
        content.title = "Claude God"
        content.body = "\(primary.label): \(Int(primary.utilization))% used"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "low-usage-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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

    // MARK: - Mise à jour automatique

    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/Lcharvol/Claude-God/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else { return }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

            DispatchQueue.main.async {
                guard Self.isNewer(remote: remoteVersion, current: Self.currentVersion) else { return }

                self?.latestVersion = remoteVersion
                self?.updateAvailable = true

                if let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                   let urlString = dmgAsset["browser_download_url"] as? String {
                    self?.downloadURL = URL(string: urlString)
                }
            }
        }.resume()
    }

    static func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }

    func installUpdate() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
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
        panel.nameFieldStringValue = "claude-usage-\(dateStamp()).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "Date,Cost,Messages,Input Tokens,Output Tokens,Cache Create,Cache Read\n"
        for day in monthStats.daily.reversed() {
            let dateStr = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: day.date)
            }()
            csv += "\(dateStr),\(String(format: "%.4f", day.cost)),\(day.messageCount),"
            csv += "\(day.tokens.inputTokens),\(day.tokens.outputTokens),"
            csv += "\(day.tokens.cacheCreationTokens),\(day.tokens.cacheReadTokens)\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
