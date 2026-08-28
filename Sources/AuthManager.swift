// AuthManager.swift
// Handles OAuth authentication, credential loading, token refresh, and token persistence

import Foundation
import Combine
import Security

// MARK: - Credential source

/// A resolved Keychain item: the credentials payload plus the coordinates it
/// was read from, so a refreshed token can be written back to that same item.
struct KeychainCredentials {
    let service: String
    let account: String?
    let json: [String: Any]
}

enum CredentialSource: String {
    case file = "credentials.json"
    case keychain = "Keychain"
    case environment = "CLAUDE_CODE_OAUTH_TOKEN"
    case none = "Not found"
}

// MARK: - Auth manager

class AuthManager: ObservableObject {

    @Published var isAuthenticated = false
    @Published var credentialSource: CredentialSource = .none
    @Published var subscriptionType: String = ""

    private(set) var accessToken: String?
    private(set) var refreshToken: String?
    private(set) var tokenExpiresAt: Double?

    private var credentialsWatcher: DispatchSourceFileSystemObject?

    /// The Keychain item credentials were last read from. Refreshed tokens are
    /// written back to this exact (service, account) pair instead of a guessed
    /// one, so we never shadow Claude Code's entry with a duplicate the app
    /// would then read instead of the real thing.
    private var keychainEntry: KeychainCredentials?
    private var isSelfRefreshing = false
    private var lastSelfRefreshFailure: Date?
    /// Callers that asked for a refresh while one was already in flight — they all
    /// get the same outcome instead of racing a second grant on the same token.
    private var selfRefreshWaiters: [(Bool) -> Void] = []

    // Refreshing OAuth tokens is Claude Code's job, not ours: the refresh token
    // is single-use and shared with the CLI, so spending it while the CLI still
    // holds the matching copy in memory forces the user to /login (issue #40).
    // The single exception is a token that has been dead for `staleTokenGrace`
    // — Claude Code rotates credentials on any use, so an entry that stale means
    // no CLI is alive to be broken. Without that exception the app is bricked
    // for anyone who stopped running `claude` in a terminal (the desktop app
    // keeps its own auth and never touches this Keychain entry).
    // `recoverSession` is the only entry point; see it below.

    static var credentialsPath: URL { ActiveAccount.credentialsFile }

    // MARK: - Credential loading

    func loadCredentials() {
        resolveCredentials { _ in }
    }

    /// Credentials JSON from the active account's `.credentials.json`, or nil if absent/unusable.
    private static func fileCredentialsJSON() -> [String: Any]? {
        guard let data = try? Data(contentsOf: credentialsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return json
    }

    private static func oauthExpiry(_ json: [String: Any]) -> Double {
        ((json["claudeAiOauth"] as? [String: Any])?["expiresAt"] as? Double) ?? 0
    }

    /// Adopt a credentials payload. Returns false if it carries no usable token.
    @discardableResult
    private func adopt(_ json: [String: Any], source: CredentialSource) -> Bool {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return false }
        accessToken = token
        refreshToken = oauth["refreshToken"] as? String
        tokenExpiresAt = oauth["expiresAt"] as? Double
        subscriptionType = oauth["subscriptionType"] as? String ?? ""
        credentialSource = source
        isAuthenticated = true
        return true
    }

    /// Resolve credentials from the freshest available source.
    ///
    /// The file is only authoritative while its token is still valid: newer Claude Code
    /// versions refresh into the Keychain (per-project entries) and leave a stale
    /// `.credentials.json` behind. Preferring the file unconditionally pinned the app to
    /// an expired token, so re-signing in never cleared "Session expired".
    private func resolveCredentials(completion: @escaping (Bool) -> Void) {
        let previousToken = accessToken
        let fileJSON = Self.fileCredentialsJSON()

        // Fast path: file token still valid — no Keychain round-trip needed.
        if let fileJSON, Self.hasFreshOAuthToken(fileJSON), adopt(fileJSON, source: .file) {
            if accessToken != previousToken { Log.info("Credentials loaded from file (type: \(subscriptionType))") }
            completion(true)
            return
        }

        // Keychain — read off the main thread to avoid blocking UI.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let keychainEntry = Self.loadFromKeychain()
            DispatchQueue.main.async {
                guard let self else { return }
                // Remember where the Keychain copy lives even when the file wins
                // below — that item is still the one a refresh must write back to.
                if let keychainEntry { self.keychainEntry = keychainEntry }

                // Both sources may be stale; take whichever token lives longest.
                let candidates: [([String: Any], CredentialSource)] = [
                    keychainEntry.map { ($0.json, CredentialSource.keychain) },
                    fileJSON.map { ($0, CredentialSource.file) }
                ].compactMap { $0 }

                if let best = candidates.max(by: { Self.oauthExpiry($0.0) < Self.oauthExpiry($1.0) }),
                   self.adopt(best.0, source: best.1) {
                    if self.accessToken != previousToken {
                        Log.info("Credentials loaded from \(best.1.rawValue) (type: \(self.subscriptionType))")
                    }
                    completion(true)
                    return
                }

                if !ActiveAccount.isPinned,
                   let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
                   !envToken.isEmpty {
                    self.accessToken = envToken
                    self.credentialSource = .environment
                    self.isAuthenticated = true
                    Log.info("Credentials loaded from environment")
                    completion(true)
                    return
                }

                Log.warn("No credentials found in file or Keychain")
                // Keep a previously loaded token: a transient read failure shouldn't
                // sign the user out.
                if previousToken == nil {
                    self.credentialSource = .none
                    self.isAuthenticated = false
                }
                completion(self.isAuthenticated)
            }
        }
    }

    // MARK: - Token management

    var tokenExpired: Bool {
        guard let expiresAt = tokenExpiresAt else { return false }
        let expiresDate = Date(timeIntervalSince1970: expiresAt / 1000)
        return Date() >= expiresDate
    }

    /// Reload credentials, preferring whichever source holds the longest-lived token.
    /// On macOS, Claude Code may store credentials exclusively in the Keychain
    /// (or refresh only there), so both sources must be compared.
    func reloadCredentials(completion: @escaping (Bool) -> Void) {
        resolveCredentials(completion: completion)
    }

    // MARK: - Session recovery

    private static let oauthTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// How long the stored access token must have been expired before this app may
    /// spend the shared refresh token. Claude Code rotates credentials on any use,
    /// so an entry dead this long belongs to no running CLI (issue #40).
    private static let staleTokenGrace: TimeInterval = 12 * 3600

    /// Cool-down after a failed self-refresh, so a broken refresh token is not
    /// retried on every poll tick.
    private static let selfRefreshRetryDelay: TimeInterval = 5 * 60

    /// Whether silent recovery is on the table: a refresh token exists, the access
    /// token has been dead longer than `staleTokenGrace`, and the last failure is
    /// old enough to retry. Stays true while an attempt is in flight — callers use
    /// this to decide whether to wait rather than prompt the user to sign in.
    var canSelfRefresh: Bool {
        if isSelfRefreshing { return true }
        guard let refreshToken, !refreshToken.isEmpty,
              let expiresAt = tokenExpiresAt else { return false }
        let deadFor = Date().timeIntervalSince(Date(timeIntervalSince1970: expiresAt / 1000))
        guard deadFor >= Self.staleTokenGrace else { return false }
        guard let lastFailure = lastSelfRefreshFailure else { return true }
        return Date().timeIntervalSince(lastFailure) >= Self.selfRefreshRetryDelay
    }

    /// Bring the session back online without user interaction when possible.
    ///
    /// Reloads from disk/Keychain first — Claude Code may have refreshed since we
    /// last looked, and adopting its token costs nothing. Only if that still leaves
    /// a long-dead token do we spend the refresh token ourselves. Completion
    /// reports whether a usable (non-expired) token is now loaded.
    func recoverSession(completion: @escaping (Bool) -> Void) {
        reloadCredentials { [weak self] _ in
            guard let self else { completion(false); return }
            if self.isAuthenticated && !self.tokenExpired {
                completion(true)
                return
            }
            guard self.canSelfRefresh else {
                completion(false)
                return
            }
            Log.info("Token dead for >\(Int(Self.staleTokenGrace / 3600))h — no live CLI can hold it, refreshing ourselves")
            self.selfRefreshToken(completion: completion)
        }
    }

    /// Silent OAuth `refresh_token` grant. Private on purpose: `recoverSession`
    /// owns the staleness gate that keeps this off an active CLI's tokens.
    /// New tokens are written back to the Keychain (and credentials file when it
    /// exists) so Claude Code picks them up on its next run.
    private func selfRefreshToken(completion: @escaping (Bool) -> Void) {
        guard let rt = refreshToken, !rt.isEmpty else {
            Log.warn("selfRefreshToken: no refresh token available")
            completion(false)
            return
        }

        // Coalesce: a second caller joins the in-flight grant instead of spending
        // the (now rotated) refresh token a second time.
        if isSelfRefreshing {
            Log.info("selfRefreshToken: grant already in flight, waiting for it")
            selfRefreshWaiters.append(completion)
            return
        }

        isSelfRefreshing = true
        Log.info("selfRefreshToken: attempting refresh_token grant")

        let finish: (Bool) -> Void = { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { completion(success); return }
                self.isSelfRefreshing = false
                self.lastSelfRefreshFailure = success ? nil : Date()
                let waiters = self.selfRefreshWaiters
                self.selfRefreshWaiters = []
                completion(success)
                waiters.forEach { $0(success) }
            }
        }

        var request = URLRequest(url: Self.oauthTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        // RFC 6749 §6 requires form-encoded bodies for token endpoint requests.
        var allowedChars = CharacterSet.alphanumerics
        allowedChars.insert(charactersIn: "-._~")
        let encodedToken = rt.addingPercentEncoding(withAllowedCharacters: allowedChars) ?? rt
        request.httpBody = "grant_type=refresh_token&refresh_token=\(encodedToken)&client_id=\(Self.oauthClientID)"
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { finish(false); return }

            if let error {
                Log.error("selfRefreshToken: network error: \(error.localizedDescription)")
                finish(false)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String, !newAccessToken.isEmpty else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "(no body)"
                Log.error("selfRefreshToken: bad response — \(body.prefix(200))")
                finish(false)
                return
            }

            let newRefreshToken = json["refresh_token"] as? String ?? rt
            let expiresIn = json["expires_in"] as? Double ?? 3600
            let newExpiresAt = (Date().timeIntervalSince1970 + expiresIn) * 1000

            DispatchQueue.main.async {
                self.accessToken = newAccessToken
                self.refreshToken = newRefreshToken
                self.tokenExpiresAt = newExpiresAt
                self.isAuthenticated = true
                Log.info("selfRefreshToken: success — new token expires in \(Int(expiresIn))s")
                self.persistRefreshedCredentials(
                    accessToken: newAccessToken,
                    refreshToken: newRefreshToken,
                    expiresAt: newExpiresAt
                )
                finish(true)
            }
        }.resume()
    }

    /// Write refreshed tokens back to the Keychain item they came from and to the
    /// credentials file when present, preserving every other field
    /// (subscriptionType, rateLimitTier, scopes) so Claude Code picks up the
    /// rotation instead of 401-ing on a token we spent.
    ///
    /// The write goes through `SecItemUpdate` rather than
    /// `security add-generic-password -U`: Claude Code's item carries no account
    /// attribute, which the CLI cannot express (`-a` is mandatory), so the CLI
    /// would happily *create* a second item that then shadows the real one on
    /// every read. `SecItemUpdate` either updates the item we read or fails.
    private func persistRefreshedCredentials(accessToken: String, refreshToken: String, expiresAt: Double) {
        guard let entry = keychainEntry else {
            Log.warn("persistRefreshedCredentials: no Keychain item on record, updating file only")
            Self.updateCredentialsFile(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            var root = entry.json
            var oauth = root["claudeAiOauth"] as? [String: Any] ?? [:]
            oauth["accessToken"] = accessToken
            oauth["refreshToken"] = refreshToken
            oauth["expiresAt"] = Int(expiresAt)
            root["claudeAiOauth"] = oauth

            guard let jsonData = try? JSONSerialization.data(withJSONObject: root) else {
                Log.error("persistRefreshedCredentials: failed to serialize JSON")
                return
            }

            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: entry.service
            ]
            // Absent account attribute → match the item however it stores it,
            // rather than inventing an empty-string account of our own.
            if let account = entry.account { query[kSecAttrAccount as String] = account }

            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: jsonData] as CFDictionary)
            if status == errSecSuccess {
                Log.info("persistRefreshedCredentials: Keychain item \(entry.service) updated")
            } else {
                // Not fatal for us — the fresh token lives in memory — but Claude Code
                // will still hold the spent one, so say so loudly.
                Log.error("persistRefreshedCredentials: SecItemUpdate failed (status \(status)) — Claude Code keeps the old token")
            }

            Self.updateCredentialsFile(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        }
    }

    /// Mirror refreshed tokens into `~/.claude/.credentials.json` when that file is
    /// the store this machine uses. No-op when it does not exist.
    private static func updateCredentialsFile(accessToken: String, refreshToken: String, expiresAt: Double) {
        guard FileManager.default.fileExists(atPath: credentialsPath.path),
              let fileData = try? Data(contentsOf: credentialsPath),
              var fileJSON = try? JSONSerialization.jsonObject(with: fileData) as? [String: Any]
        else { return }

        var oauth = fileJSON["claudeAiOauth"] as? [String: Any] ?? [:]
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = Int(expiresAt)
        fileJSON["claudeAiOauth"] = oauth

        guard let newData = try? JSONSerialization.data(withJSONObject: fileJSON) else {
            Log.error("updateCredentialsFile: failed to serialize JSON")
            return
        }
        do {
            try newData.write(to: credentialsPath)
            Log.info("updateCredentialsFile: credentials file updated")
        } catch {
            Log.error("updateCredentialsFile: write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Credentials file watcher

    func startWatchingCredentials() {
        stopWatchingCredentials()

        let path = Self.credentialsPath.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Small delay to let the file finish writing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let wasAuthenticated = self.isAuthenticated
                self.loadCredentials()
                if !wasAuthenticated && self.isAuthenticated {
                    Log.info("Credentials detected via file watcher")
                }
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        credentialsWatcher = source
    }

    private func stopWatchingCredentials() {
        credentialsWatcher?.cancel()
        credentialsWatcher = nil
    }

    deinit {
        stopWatchingCredentials()
    }

    // MARK: - Keychain

    /// Load credentials from Keychain.
    ///
    /// Tries cheap, non-prompting `/usr/bin/security` shell-outs first (no keychain
    /// access dialog), and only falls back to the direct Security framework API —
    /// which can trigger a one-time "Claude God wants to access the keychain"
    /// prompt — when those fail. Most users have an entry whose account matches
    /// `$USER`, so the per-account fast path resolves cleanly without any prompt.
    ///
    /// Order:
    ///   1. `security find-generic-password -s <active account's service>` (no `-a`)
    ///   2. `security find-generic-password -s <active account's service> -a $USER`
    ///   3. `SecItemCopyMatching` scan — prefix-matched when no explicit account
    ///      is selected (covers per-project suffixed entries from newer Claude
    ///      Code versions), but exact-matched for a pinned account: the
    ///      freshest-token prefix scan would otherwise resolve to whichever
    ///      *other* account refreshed most recently.
    static func loadFromKeychain() -> KeychainCredentials? {
        let service = ActiveAccount.keychainService

        if let json = readKeychainViaSecurityCLI(service: service, account: nil),
           hasFreshOAuthToken(json) {
            return KeychainCredentials(service: service, account: nil, json: json)
        }

        let user = NSUserName()
        if !user.isEmpty,
           let json = readKeychainViaSecurityCLI(service: service, account: user),
           hasFreshOAuthToken(json) {
            return KeychainCredentials(service: service, account: user, json: json)
        }

        return loadBestKeychainEntry(matching: service, exact: ActiveAccount.isPinned)
    }

    private static func readKeychainViaSecurityCLI(service: String, account: String?) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        var args = ["find-generic-password", "-s", service]
        if let account = account { args.append(contentsOf: ["-a", account]) }
        args.append("-w")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let trimmed = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  let jsonData = trimmed.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { return nil }
            return json
        } catch {
            return nil
        }
    }

    private static func hasFreshOAuthToken(_ json: [String: Any]) -> Bool {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              let expiresAt = oauth["expiresAt"] as? Double else { return false }
        return Date(timeIntervalSince1970: expiresAt / 1000) > Date()
    }

    private static func loadBestKeychainEntry(matching target: String, exact: Bool) -> KeychainCredentials? {
        // The legacy file-based login keychain rejects kSecReturnAttributes+kSecReturnData
        // together with kSecMatchLimitAll (returns errSecParam). Enumerate refs+attributes
        // first, then fetch each item's data with a per-item query.
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var listRaw: CFTypeRef?
        let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &listRaw)
        guard listStatus == errSecSuccess,
              let items = listRaw as? [[String: Any]] else {
            Log.info("loadBestKeychainEntry: list query failed status=\(listStatus)")
            return nil
        }

        var best: KeychainCredentials?
        var bestExpiry: Double = 0

        for item in items {
            guard let service = item[kSecAttrService as String] as? String,
                  exact ? service == target : service.hasPrefix(target) else { continue }
            let account = item[kSecAttrAccount as String] as? String ?? ""

            // ponytail: use CLI (no-prompt) instead of SecItemCopyMatching+kSecReturnData (prompts)
            guard let json = readKeychainViaSecurityCLI(service: service, account: account.isEmpty ? nil : account),
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty
            else { continue }

            let expiresAt = oauth["expiresAt"] as? Double ?? 0
            if expiresAt > bestExpiry {
                bestExpiry = expiresAt
                best = KeychainCredentials(service: service, account: account.isEmpty ? nil : account, json: json)
            }
        }

        if let best {
            Log.info("loadBestKeychainEntry: using entry service=\(best.service) account=\(best.account ?? "<empty>") (target: \(target), exact: \(exact))")
        }
        return best
    }
}
