// AppShortcuts.swift
// Shortcuts.app integration via AppIntents framework

import AppIntents

@available(macOS 14.0, *)
struct GetUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Claude Usage"
    static var description = IntentDescription("Returns current Claude AI quota usage percentages")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let quotas = await MainActor.run { UsageManager.shared?.quotas ?? [] }

        if quotas.isEmpty {
            return .result(value: "No quota data available. Open Claude God to refresh.")
        }

        let lines = quotas.map { "\($0.label): \(Int($0.utilization))% used" }
        return .result(value: lines.joined(separator: "\n"))
    }
}

@available(macOS 14.0, *)
struct GetCostIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Claude Cost"
    static var description = IntentDescription("Returns today's Claude AI usage cost")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let (today, week) = await MainActor.run {
            (UsageManager.shared?.todayStats ?? UsageStats(),
             UsageManager.shared?.weekStats ?? UsageStats())
        }

        let fmt: (Double) -> String = { cost in
            cost >= 0.01 ? String(format: "$%.2f", cost) : String(format: "$%.3f", cost)
        }

        return .result(value: "Today: \(fmt(today.totalCost)) (\(today.totalMessages) msgs)\n7 days: \(fmt(week.totalCost)) (\(week.totalMessages) msgs)")
    }
}

@available(macOS 14.0, *)
struct RefreshUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Claude Usage"
    static var description = IntentDescription("Refreshes Claude AI quota data")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await MainActor.run {
            UsageManager.shared?.refresh()
        }
        return .result(value: "Refreshing Claude usage data...")
    }
}

@available(macOS 14.0, *)
struct ClaudeGodShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetUsageIntent(),
            phrases: [
                "Get my Claude usage with \(.applicationName)",
                "Show Claude quotas with \(.applicationName)"
            ],
            shortTitle: "Claude Usage",
            systemImageName: "c.circle"
        )
        AppShortcut(
            intent: GetCostIntent(),
            phrases: [
                "Get my Claude cost with \(.applicationName)",
                "How much Claude today with \(.applicationName)"
            ],
            shortTitle: "Claude Cost",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: RefreshUsageIntent(),
            phrases: [
                "Refresh Claude usage with \(.applicationName)"
            ],
            shortTitle: "Refresh Claude",
            systemImageName: "arrow.clockwise"
        )
    }
}
