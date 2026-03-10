// UsageManager.swift
// Gère la logique : appels API, stockage des données, calculs, notifications

import Foundation
import Combine
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

// MARK: - Manager principal

class UsageManager: ObservableObject {

    // MARK: - Données d'utilisation

    @Published var tokensRemaining: Int = 0
    @Published var tokensLimit: Int = 0
    @Published var requestsRemaining: Int = 0
    @Published var requestsLimit: Int = 0
    @Published var resetTime: Date? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastRefresh: Date? = nil

    // MARK: - État de l'interface

    @Published var apiKey: String = ""
    @Published var apiKeySource: APIKeySource = .manual
    @Published var showSettings: Bool = false

    // MARK: - Mise à jour

    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var downloadURL: URL? = nil
    static let currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

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

    // MARK: - Timers

    private var countdownTimer: AnyCancellable?
    private var autoRefreshTimer: AnyCancellable?
    private var resetCheckTimer: AnyCancellable?
    private var hasNotifiedLowUsage: Bool = false

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
                self?.objectWillChange.send()
                self?.checkResetExpired()
            }

        // Configurer l'auto-refresh
        setupAutoRefresh()

        // Demander les permissions de notification
        if notificationsEnabled {
            requestNotificationPermission()
        }

        // Rafraîchir au lancement si on a une clé
        if !apiKey.isEmpty {
            refresh()
        }

        // Vérifier les mises à jour
        checkForUpdates()
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

    var menuBarTitle: String {
        guard tokensLimit > 0 else { return "—" }
        return "\(Int(tokensPercent))%"
    }

    var timeUntilReset: String {
        guard let reset = resetTime else { return "—" }
        let remaining = reset.timeIntervalSinceNow
        if remaining <= 0 { return "now" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }

    /// Couleur selon le niveau d'utilisation (pour l'icône menu bar)
    var statusColor: String {
        if tokensLimit == 0 { return "secondary" }
        if tokensPercent > 50 { return "green" }
        if tokensPercent > 20 { return "orange" }
        return "red"
    }

    // MARK: - Actions

    func saveAPIKey() {
        KeychainHelper.save(key: "apiKey", value: apiKey)
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
    }

    func refresh() {
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

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.errorMessage = "Invalid response"
                    return
                }

                if httpResponse.statusCode == 401 {
                    self?.errorMessage = "Invalid API key"
                    return
                }

                if httpResponse.statusCode == 403 {
                    self?.errorMessage = "Access denied"
                    return
                }

                if httpResponse.statusCode == 429 {
                    self?.errorMessage = "Rate limited — try again later"
                    // On parse quand même les headers car ils sont présents sur les 429
                    self?.parseRateLimitHeaders(httpResponse)
                    self?.lastRefresh = Date()
                    return
                }

                self?.parseRateLimitHeaders(httpResponse)
                self?.lastRefresh = Date()
                self?.checkLowUsageNotification()
            }
        }.resume()
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

    /// Vérifie si le reset est passé et rafraîchit automatiquement
    private func checkResetExpired() {
        guard let reset = resetTime else { return }
        if reset.timeIntervalSinceNow <= 0 && lastRefresh != nil {
            // Le reset vient d'expirer — rafraîchir pour avoir les nouvelles limites
            resetTime = nil
            hasNotifiedLowUsage = false
            refresh()
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkLowUsageNotification() {
        guard notificationsEnabled else { return }
        guard tokensLimit > 0 else { return }
        guard tokensPercent <= notificationThreshold else {
            hasNotifiedLowUsage = false
            return
        }
        guard !hasNotifiedLowUsage else { return }

        hasNotifiedLowUsage = true

        let content = UNMutableNotificationContent()
        content.title = "Claude God"
        content.body = "Tokens remaining: \(Int(tokensPercent))% (\(formatCompact(tokensRemaining)) left)"
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
        if #available(macOS 13.0, *) {
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
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetTime = formatter.date(from: value)
        }
    }

    // MARK: - Helpers

    private func formatCompact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Migre la clé API depuis UserDefaults (ancien stockage) vers Keychain
    private func migrateAPIKeyFromUserDefaults() {
        if apiKey.isEmpty, let oldKey = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !oldKey.isEmpty {
            apiKey = oldKey
            apiKeySource = .keychain
            KeychainHelper.save(key: "apiKey", value: oldKey)
            UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
        }
    }

    /// Auto-détection de la clé API depuis le fichier Anthropic CLI ou l'env var
    private func autoDetectAPIKey() {
        guard apiKey.isEmpty else {
            apiKeySource = .keychain
            return
        }

        // 1. Chercher dans ~/.anthropic/api_key (fichier du CLI Anthropic)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let filePath = home.appendingPathComponent(".anthropic/api_key")
        if let fileKey = try? String(contentsOf: filePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fileKey.isEmpty {
            apiKey = fileKey
            apiKeySource = .file
            KeychainHelper.save(key: "apiKey", value: fileKey)
            return
        }

        // 2. Chercher la variable d'environnement ANTHROPIC_API_KEY
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !envKey.isEmpty {
            apiKey = envKey
            apiKeySource = .environment
            KeychainHelper.save(key: "apiKey", value: envKey)
            return
        }
    }

    // MARK: - Mise à jour automatique

    /// Vérifie sur GitHub si une nouvelle version est disponible
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
            let currentVersion = UsageManager.currentVersion

            DispatchQueue.main.async {
                if self?.isNewer(remote: remoteVersion, current: currentVersion) == true {
                    self?.latestVersion = remoteVersion
                    self?.updateAvailable = true

                    // Trouver l'URL du DMG dans les assets
                    if let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                       let urlString = dmgAsset["browser_download_url"] as? String {
                        self?.downloadURL = URL(string: urlString)
                    }
                }
            }
        }.resume()
    }

    /// Compare deux versions semver (ex: "1.2.0" > "1.1.0")
    private func isNewer(remote: String, current: String) -> Bool {
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

    /// Télécharge et installe la mise à jour
    func installUpdate() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
    }
}
