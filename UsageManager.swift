// UsageManager.swift
// Gère la logique : appels API, stockage des données, calculs

import Foundation
import Combine

class UsageManager: ObservableObject {

    // MARK: - Données publiées (la vue se met à jour automatiquement quand elles changent)

    @Published var tokensRemaining: Int = 0
    @Published var tokensLimit: Int = 0
    @Published var requestsRemaining: Int = 0
    @Published var requestsLimit: Int = 0
    @Published var resetTime: Date? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var apiKey: String = ""
    @Published var showSettings: Bool = false
    @Published var lastRefresh: Date? = nil

    // Timer pour mettre à jour le compte à rebours chaque seconde
    private var countdownTimer: AnyCancellable?

    // MARK: - Initialisation

    init() {
        // Charger la clé API sauvegardée
        self.apiKey = UserDefaults.standard.string(forKey: "anthropicAPIKey") ?? ""

        // Démarrer le timer du compte à rebours
        countdownTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                // Force la vue à se rafraîchir (pour le compte à rebours)
                self?.objectWillChange.send()
            }

        // Si on a déjà une clé, rafraîchir au lancement
        if !apiKey.isEmpty {
            refresh()
        }
    }

    // MARK: - Propriétés calculées

    /// Pourcentage de tokens restants (ex: 75 = il reste 75%)
    var tokensPercent: Double {
        guard tokensLimit > 0 else { return 0 }
        return Double(tokensRemaining) / Double(tokensLimit) * 100
    }

    /// Pourcentage de requêtes restantes
    var requestsPercent: Double {
        guard requestsLimit > 0 else { return 0 }
        return Double(requestsRemaining) / Double(requestsLimit) * 100
    }

    /// Texte affiché dans la barre de menu
    var menuBarTitle: String {
        guard tokensLimit > 0 else { return "—" }
        return "\(Int(tokensPercent))%"
    }

    /// Temps restant avant le reset, formaté en texte lisible
    var timeUntilReset: String {
        guard let reset = resetTime else { return "—" }
        let remaining = reset.timeIntervalSinceNow
        if remaining <= 0 { return "maintenant" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }

    // MARK: - Actions

    /// Sauvegarder la clé API
    func saveAPIKey() {
        UserDefaults.standard.set(apiKey, forKey: "anthropicAPIKey")
    }

    /// Supprimer la clé API
    func clearAPIKey() {
        apiKey = ""
        UserDefaults.standard.removeObject(forKey: "anthropicAPIKey")
        tokensRemaining = 0
        tokensLimit = 0
        requestsRemaining = 0
        requestsLimit = 0
        resetTime = nil
        lastRefresh = nil
    }

    /// Appeler l'API Anthropic pour récupérer les limites d'utilisation
    func refresh() {
        guard !apiKey.isEmpty else {
            errorMessage = "Clé API manquante"
            return
        }

        isLoading = true
        errorMessage = nil

        // Construire la requête HTTP
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Requête minimale : 1 seul token de réponse pour minimiser le coût
        // Coût : quasi nul (quelques fractions de centime)
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Envoyer la requête
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            // Revenir sur le thread principal pour mettre à jour l'UI
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.errorMessage = "Réponse invalide"
                    return
                }

                // Vérifier le code HTTP
                if httpResponse.statusCode == 401 {
                    self?.errorMessage = "Clé API invalide"
                    return
                }

                if httpResponse.statusCode == 403 {
                    self?.errorMessage = "Accès refusé"
                    return
                }

                // Lire les headers de rate limit
                // L'API Anthropic renvoie ces infos dans chaque réponse
                self?.parseRateLimitHeaders(httpResponse)
                self?.lastRefresh = Date()
            }
        }.resume()
    }

    /// Extraire les informations de rate limit des headers HTTP
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
}
