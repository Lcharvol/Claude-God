// AuthManager.swift
// Handles OAuth authentication, credential loading, token refresh, and token persistence

import Foundation
import Combine
import Security

// MARK: - Credential source

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

    // OAuth refresh is intentionally NOT done by this app. Claude Code owns
    // the single-use refresh-token cycle; if we consume the token, the CLI's
    // in-memory copy becomes stale and the user is forced to /login again on
    // the next `claude` invocation. See issue #40 and the note further down
    // where `selfRefreshToken` used to live.

    static let credentialsPath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }()

    // MARK: - Credential loading

    func loadCredentials() {
        resolveCredentials { _ in }
    }

    /// Credentials JSON from `~/.claude/.credentials.json`, or nil if absent/unusable.
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
            let keychainJSON = Self.loadFromKeychain()
            DispatchQueue.main.async {
                guard let self else { return }

                // Both sources may be stale; take whichever token lives longest.
                let candidates: [([String: Any], CredentialSource)] = [
                    keychainJSON.map { ($0, CredentialSource.keychain) },
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

                if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
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

    // NOTE: There is no silent OAuth `refresh_token` grant in this app on purpose.
    // Claude Code's refresh token is single-use and shared with the CLI: if we
    // spent it, the CLI's in-memory token would 401 and force `/login` again
    // (see issue #40). When our token expires we reload from disk/Keychain in
    // case Claude Code has since refreshed it, and otherwise ask the user to
    // run `claude auth login`.

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
    ///   1. `security find-generic-password -s "Claude Code-credentials"` (no `-a`)
    ///   2. `security find-generic-password -s "Claude Code-credentials" -a $USER`
    ///   3. `SecItemCopyMatching` scan over all `Claude Code-credentials*` entries
    ///      (covers per-project suffixed entries from newer Claude Code versions)
    static func loadFromKeychain() -> [String: Any]? {
        if let json = readKeychainViaSecurityCLI(service: "Claude Code-credentials", account: nil),
           hasFreshOAuthToken(json) {
            return json
        }

        let user = NSUserName()
        if !user.isEmpty,
           let json = readKeychainViaSecurityCLI(service: "Claude Code-credentials", account: user),
           hasFreshOAuthToken(json) {
            return json
        }

        return loadBestKeychainEntryWithPrefix("Claude Code-credentials")
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

    private static func loadBestKeychainEntryWithPrefix(_ prefix: String) -> [String: Any]? {
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
            Log.info("loadBestKeychainEntryWithPrefix: list query failed status=\(listStatus)")
            return nil
        }

        var bestJSON: [String: Any]?
        var bestExpiry: Double = 0
        var bestAccount: String = ""

        for item in items {
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(prefix) else { continue }
            let account = item[kSecAttrAccount as String] as? String ?? ""

            // ponytail: use CLI (no-prompt) instead of SecItemCopyMatching+kSecReturnData (prompts)
            guard let json = readKeychainViaSecurityCLI(service: service, account: account.isEmpty ? nil : account),
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty
            else { continue }

            let expiresAt = oauth["expiresAt"] as? Double ?? 0
            if expiresAt > bestExpiry {
                bestExpiry = expiresAt
                bestJSON = json
                bestAccount = account
            }
        }

        if bestJSON != nil {
            Log.info("loadBestKeychainEntryWithPrefix: using entry account=\(bestAccount.isEmpty ? "<empty>" : bestAccount) (prefix: \(prefix))")
        }
        return bestJSON
    }
}
