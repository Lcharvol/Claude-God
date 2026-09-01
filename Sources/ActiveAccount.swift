// ActiveAccount.swift
// Where the currently selected account keeps its data.
//
// Claude Code namespaces everything by config directory: with CLAUDE_CONFIG_DIR
// unset it uses ~/.claude and the Keychain service "Claude Code-credentials";
// with CLAUDE_CONFIG_DIR=D it uses D and the service
// "Claude Code-credentials-<h>", where <h> is the first 8 hex characters of
// sha256(D). Pointing this store at an account's config dir is what makes
// credential loading, session analytics and the file watcher all follow the
// account the user picked in the popover instead of whichever token happens
// to be freshest.

import Foundation
import CryptoKit

enum ActiveAccount {
    /// Config dir of the active account; nil = the default ~/.claude login.
    /// Only mutated on the main thread (startup and switchAccount).
    static var configDir: String?

    /// The directory holding this account's data (projects/, .credentials.json).
    static var dataDir: URL {
        configDir.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    static var credentialsFile: URL { dataDir.appendingPathComponent(".credentials.json") }

    static var keychainService: String {
        guard let dir = configDir else { return "Claude Code-credentials" }
        let hash = SHA256.hash(data: Data(dir.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(8)
        return "Claude Code-credentials-\(hash)"
    }

    /// Whether an explicit non-default account is selected. When true the
    /// Keychain lookup must match this exact service — the freshest-token
    /// prefix scan would bleed one account's credentials into another's view.
    static var isPinned: Bool { configDir != nil }
}
