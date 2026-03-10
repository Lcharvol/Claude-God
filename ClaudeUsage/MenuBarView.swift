// MenuBarView.swift
// L'interface qui s'affiche quand on clique sur l'icône dans la menu bar

import SwiftUI

// MARK: - Vue principale

struct MenuBarView: View {
    @ObservedObject var manager: UsageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // -- En-tête --
            header

            Divider()

            // -- Contenu principal --
            if manager.apiKey.isEmpty || manager.showSettings {
                settingsView
            } else if manager.isLoading && manager.lastRefresh == nil {
                // Premier chargement
                ProgressView("Chargement...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if let error = manager.errorMessage {
                errorView(error)
            } else if manager.tokensLimit > 0 {
                usageView
            } else {
                Text("Cliquez sur Rafraîchir")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Divider()

            // -- Boutons du bas --
            bottomBar
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Sous-vues

    /// En-tête avec titre et bouton réglages
    private var header: some View {
        HStack {
            Image(systemName: "c.circle.fill")
                .foregroundColor(.purple)
                .font(.title3)
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            // Bouton pour afficher/masquer les réglages
            Button(action: { manager.showSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Vue des réglages (saisie de la clé API)
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clé API Anthropic")
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField("sk-ant-api03-...", text: $manager.apiKey)
                .textFieldStyle(.roundedBorder)

            Text("Trouvez votre clé sur console.anthropic.com")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Sauvegarder") {
                    manager.saveAPIKey()
                    manager.showSettings = false
                    manager.refresh()
                }
                .disabled(manager.apiKey.isEmpty)

                if !manager.apiKey.isEmpty {
                    Button("Supprimer") {
                        manager.clearAPIKey()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }

    /// Vue d'erreur
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.title2)
            Text(error)
                .foregroundColor(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Vue principale avec les données d'utilisation
    private var usageView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Barre de tokens
            UsageRow(
                label: "Tokens",
                remaining: manager.tokensRemaining,
                limit: manager.tokensLimit,
                percent: manager.tokensPercent
            )

            // Barre de requêtes
            UsageRow(
                label: "Requêtes",
                remaining: manager.requestsRemaining,
                limit: manager.requestsLimit,
                percent: manager.requestsPercent
            )

            Divider()

            // Temps avant reset
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Reset dans :")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(manager.timeUntilReset)
                    .font(.caption.monospacedDigit())
                    .fontWeight(.medium)
            }

            // Dernière mise à jour
            if let lastRefresh = manager.lastRefresh {
                HStack {
                    Spacer()
                    Text("Mis à jour : \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Barre de boutons en bas
    private var bottomBar: some View {
        HStack {
            Button(action: { manager.refresh() }) {
                HStack(spacing: 4) {
                    if manager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Rafraîchir")
                }
            }
            .disabled(manager.apiKey.isEmpty || manager.isLoading)

            Spacer()

            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Composant : ligne d'utilisation avec barre de progression

struct UsageRow: View {
    let label: String
    let remaining: Int
    let limit: Int
    let percent: Double

    /// Couleur selon le pourcentage restant
    private var barColor: Color {
        if percent > 50 { return .green }
        if percent > 20 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Label + pourcentage
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(percent))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(barColor)
                    .fontWeight(.semibold)
            }

            // Barre de progression
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Fond gris
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    // Barre colorée
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(percent / 100))
                }
            }
            .frame(height: 8)

            // Détail : remaining / limit
            Text("\(formatNumber(remaining)) / \(formatNumber(limit))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// Formate un nombre avec des séparateurs de milliers (ex: 80 000)
    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
