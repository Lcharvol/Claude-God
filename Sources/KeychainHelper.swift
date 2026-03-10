// KeychainHelper.swift
// Stockage sécurisé de la clé API dans le Keychain macOS
// Le Keychain est chiffré par le système — bien plus sûr que UserDefaults

import Foundation
import Security

enum KeychainHelper {

    private static let service = "com.lcharvol.claude-god"

    /// Sauvegarder une valeur dans le Keychain
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Supprimer l'ancienne valeur si elle existe
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    /// Lire une valeur depuis le Keychain
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Supprimer une valeur du Keychain
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
