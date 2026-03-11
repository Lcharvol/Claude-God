// ClaudeUsageApp.swift
// Point d'entrée — crée l'icône dans la menu bar macOS

import SwiftUI

@main
struct ClaudeGodApp: App {
    @StateObject private var manager = UsageManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: manager.menuBarIcon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(manager.menuBarIconColor)
                if manager.isSessionActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 5, height: 5)
                }
                Text(manager.menuBarTitle)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
