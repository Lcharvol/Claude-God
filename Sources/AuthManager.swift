// AuthManager.swift
// Handles OAuth authentication, credential loading, token refresh, and token persistence

import Foundation
import Combine

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

    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scopes = "user:profile user:inference user:sessions:claude_code"

    static let credentialsPath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }()

    // MARK: - Credential loading

    func loadCredentials() {
        // 1. File ~/.claude/.credentials.json
        if let data = try? Data(contentsOf: Self.credentialsPath),
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

        // 3. Environment variable
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

    // MARK: - Token management

    var tokenNeedsRefresh: Bool {
        guard let expiresAt = tokenExpiresAt else { return true }
        let expiresDate = Date(timeIntervalSince1970: expiresAt / 1000)
        return Date().addingTimeInterval(5 * 60) >= expiresDate
    }

    func refreshAccessToken(completion: @escaping (Bool) -> Void) {
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
                self.persistTokens()
                completion(true)
            }
        }.resume()
    }

    // MARK: - Token persistence

    private func persistTokens() {
        guard credentialSource == .file else { return }

        do {
            let data = try Data(contentsOf: Self.credentialsPath)
            guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var oauth = json["claudeAiOauth"] as? [String: Any]
            else { return }

            oauth["accessToken"] = accessToken
            if let rt = refreshToken { oauth["refreshToken"] = rt }
            if let exp = tokenExpiresAt { oauth["expiresAt"] = exp }
            json["claudeAiOauth"] = oauth

            let updated = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try updated.write(to: Self.credentialsPath, options: .atomic)
            print("[ClaudeGod] Tokens persisted to credentials file")
        } catch {
            print("[ClaudeGod] Failed to persist tokens: \(error.localizedDescription)")
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
                    print("[ClaudeGod] Credentials detected via file watcher")
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

            let rawData = pipe.fileHandleForReading.readDataToEndOfFile()
            // Trim whitespace from raw output before parsing
            guard let trimmed = String(data: rawData, encoding: .utf8)?
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
}
