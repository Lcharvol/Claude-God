// UsageManager.swift
// Gère la logique : appels API, stockage des données, calculs, notifications

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

// MARK: - Source de la clé API

enum APIKeySource: String {
    case manual = "Manual"
    case keychain = "Keychain"
    case file = "~/.anthropic/api_key"
    case environment = "ANTHROPIC_API_KEY"
}

// MARK: - Seuils de couleur partagés

enum UsageLevel {
    case good, warning, critical

    init(percent: Double) {
        if percent > 50 { self = .good }
        else if percent > 20 { self = .warning }
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

// MARK: - Formatters statiques (évite les allocations répétées)

enum Formatters {
    static let resetDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f
    }()

    static func formatNumber(_ n: Int) -> String {
        number.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Manager principal

class UsageManager: ObservableObject {

    // MARK: - Données d'utilisation

    @Published var tokensRemaining = 0
    @Published var tokensLimit = 0
    @Published var requestsRemaining = 0
    @Published var requestsLimit = 0
    @Published var resetTime: Date?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefresh: Date?
    @Published var timeUntilReset: String = "—"

    // MARK: - État de l'interface

    @Published var apiKey = ""
    @Published var apiKeySource: APIKeySource = .manual
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

    // MARK: - Propriétés calculées

    var tokensPercent: Double {
        guard tokensLimit > 0 else { return 0 }
        return Double(tokensRemaining) / Double(tokensLimit) * 100
    }

    var requestsPercent: Double {
        guard requestsLimit > 0 else { return 0 }
        return Double(requestsRemaining) / Double(requestsLimit) * 100
    }

    var tokensLevel: UsageLevel { UsageLevel(percent: tokensPercent) }
    var requestsLevel: UsageLevel { UsageLevel(percent: requestsPercent) }

    var menuBarTitle: String {
        guard tokensLimit > 0 else { return "—" }
        return "\(Int(tokensPercent))%"
    }

    // MARK: - Timers

    private var countdownTimer: AnyCancellable?
    private var autoRefreshTimer: AnyCancellable?
    private var hasNotifiedLowUsage = false

    /// Cooldown minimum entre deux refresh automatiques (secondes)
    private let autoRefreshCooldown: TimeInterval = 30

    // MARK: - Initialisation

    init() {
        // Charger les préférences
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .fiveMin
        self.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.notificationThreshold = UserDefaults.standard.object(forKey: "notificationThreshold") as? Double ?? 20.0
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")

        // Charger la clé API (Keychain > fichier > env var)
        self.apiKey = KeychainHelper.load(key: "apiKey") ?? ""
        migrateAPIKeyFromUserDefaults()
        autoDetectAPIKey()

        // Timer de compte à rebours (1 seconde)
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateCountdown()
                self?.checkResetExpired()
            }

        setupAutoRefresh()

        if notificationsEnabled {
            requestNotificationPermission()
        }

        if !apiKey.isEmpty {
            refresh()
        }

        checkForUpdates()
    }

    // MARK: - Actions

    func saveAPIKey() {
        KeychainHelper.save(key: "apiKey", value: apiKey)
        apiKeySource = .keychain
    }

    func clearAPIKey() {
        apiKey = ""
        KeychainHelper.delete(key: "apiKey")
        tokensRemaining = 0
        tokensLimit = 0
        requestsRemaining = 0
        requestsLimit = 0
        resetTime = nil
        lastRefresh = nil
        errorMessage = nil
        hasNotifiedLowUsage = false
        timeUntilReset = "—"
    }

    func refresh() {
        guard !isLoading else { return }
        guard !apiKey.isEmpty else {
            errorMessage = "API key missing"
            return
        }

        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "h"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
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
                    print("[ClaudeGod] No HTTP response")
                    return
                }

                print("[ClaudeGod] HTTP \(httpResponse.statusCode)")

                switch httpResponse.statusCode {
                case 200...299:
                    self.parseRateLimitHeaders(httpResponse)
                    self.lastRefresh = Date()
                    self.checkLowUsageNotification()
                case 401:
                    self.errorMessage = "Invalid API key"
                case 403:
                    self.errorMessage = "Access denied"
                case 429:
                    self.errorMessage = "Rate limited — try again later"
                    self.parseRateLimitHeaders(httpResponse)
                    self.lastRefresh = Date()
                default:
                    // Lire le body pour avoir le message d'erreur de l'API
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let apiError = json["error"] as? [String: Any],
                       let message = apiError["message"] as? String {
                        self.errorMessage = message
                        print("[ClaudeGod] API error: \(message)")
                    } else {
                        self.errorMessage = "Error \(httpResponse.statusCode)"
                        print("[ClaudeGod] Unknown error \(httpResponse.statusCode)")
                    }
                }
            }
        }
        task.resume()
    }

    // MARK: - Countdown

    /// Met à jour le texte du compte à rebours (appelé chaque seconde)
    private func updateCountdown() {
        guard let reset = resetTime else {
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

    /// Vérifie si le reset est passé et rafraîchit automatiquement (avec cooldown)
    private func checkResetExpired() {
        guard let reset = resetTime, lastRefresh != nil else { return }
        guard reset.timeIntervalSinceNow <= 0 else { return }

        // Cooldown : évite une boucle si le serveur renvoie un resetTime dans le passé
        if let last = lastRefresh, Date().timeIntervalSince(last) < autoRefreshCooldown { return }

        resetTime = nil
        hasNotifiedLowUsage = false
        refresh()
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkLowUsageNotification() {
        guard notificationsEnabled, tokensLimit > 0 else { return }
        guard tokensPercent <= notificationThreshold else {
            hasNotifiedLowUsage = false
            return
        }
        guard !hasNotifiedLowUsage else { return }

        hasNotifiedLowUsage = true

        let content = UNMutableNotificationContent()
        content.title = "Claude God"
        content.body = "Tokens remaining: \(Int(tokensPercent))% (\(Formatters.formatCompact(tokensRemaining)) left)"
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
            // Silently ignore — user may not have granted permission
        }
    }

    // MARK: - Parsing

    private func parseRateLimitHeaders(_ response: HTTPURLResponse) {
        if let value = response.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-limit") {
            tokensLimit = Int(value) ?? 0
        }
        if let value = response.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-remaining") {
            tokensRemaining = Int(value) ?? 0
        }
        if let value = response.value(forHTTPHeaderField: "anthropic-ratelimit-requests-limit") {
            requestsLimit = Int(value) ?? 0
        }
        if let value = response.value(forHTTPHeaderField: "anthropic-ratelimit-requests-remaining") {
            requestsRemaining = Int(value) ?? 0
        }
        if let value = response.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-reset") {
            resetTime = Formatters.resetDate.date(from: value)
        }
    }

    // MARK: - Migration & Auto-détection

    private func migrateAPIKeyFromUserDefaults() {
        if apiKey.isEmpty, let oldKey = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !oldKey.isEmpty {
            apiKey = oldKey
            apiKeySource = .keychain
            KeychainHelper.save(key: "apiKey", value: oldKey)
            UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
        }
    }

    private func autoDetectAPIKey() {
        guard apiKey.isEmpty else {
            apiKeySource = .keychain
            return
        }

        // 1. Fichier ~/.anthropic/api_key (CLI Anthropic)
        let filePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".anthropic/api_key")
        if let fileKey = try? String(contentsOf: filePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fileKey.isEmpty {
            apiKey = fileKey
            apiKeySource = .file
            KeychainHelper.save(key: "apiKey", value: fileKey)
            return
        }

        // 2. Variable d'environnement ANTHROPIC_API_KEY
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !envKey.isEmpty {
            apiKey = envKey
            apiKeySource = .environment
            KeychainHelper.save(key: "apiKey", value: envKey)
            return
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

    /// Compare deux versions semver (ex: "1.2.0" > "1.1.0")
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
}
