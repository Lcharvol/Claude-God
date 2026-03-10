// ClaudeUsageApp.swift
// Point d'entrée de l'application
// C'est ici que l'app démarre et crée l'icône dans la menu bar

import SwiftUI

@main
struct ClaudeUsageApp: App {
    // Le "manager" gère toutes les données et appels API
    // @StateObject = l'app garde cet objet en vie tant qu'elle tourne
    @StateObject private var manager = UsageManager()

    var body: some Scene {
        // MenuBarExtra = crée une icône dans la barre de menu macOS
        MenuBarExtra {
            // Ce qui s'affiche quand on clique sur l'icône
            MenuBarView(manager: manager)
        } label: {
            // Ce qui s'affiche DANS la barre de menu (icône + texte)
            HStack(spacing: 4) {
                Image(systemName: "c.circle")
                Text(manager.menuBarTitle)
                    .monospacedDigit()
            }
        }
        // .window = affiche un vrai popover (pas un simple menu déroulant)
        .menuBarExtraStyle(.window)
    }
}
