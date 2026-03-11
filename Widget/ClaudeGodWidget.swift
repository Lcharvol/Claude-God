// ClaudeGodWidget.swift
// macOS Desktop Widget — shows Claude quota gauges

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct QuotaEntry: TimelineEntry {
    let date: Date
    let quotas: [QuotaInfo]
    let todayCost: Double
    let todayMessages: Int

    static let placeholder = QuotaEntry(
        date: Date(),
        quotas: [
            QuotaInfo(label: "Session", utilization: 42, color: .green),
            QuotaInfo(label: "Weekly", utilization: 28, color: .green),
            QuotaInfo(label: "Sonnet", utilization: 15, color: .green),
            QuotaInfo(label: "Opus", utilization: 67, color: .orange)
        ],
        todayCost: 1.23,
        todayMessages: 45
    )
}

struct QuotaInfo: Identifiable {
    let id = UUID()
    let label: String
    let utilization: Double
    let color: Color
}

struct ClaudeGodProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let entry = makeEntry()
        // Refresh every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> QuotaEntry {
        // Read cached quota data from shared UserDefaults (app group)
        let defaults = UserDefaults(suiteName: "group.com.lcharvol.claude-god") ?? .standard
        let quotas: [QuotaInfo]
        let todayCost: Double
        let todayMessages: Int

        if let data = defaults.data(forKey: "widgetQuotas"),
           let decoded = try? JSONDecoder().decode([[String: Double]].self, from: data) {
            quotas = decoded.map { dict in
                let util = dict["utilization"] ?? 0
                let color: Color = util < 50 ? .green : util < 80 ? .orange : .red
                return QuotaInfo(
                    label: dict["labelIndex"].flatMap { idx in
                        let labels = ["Session", "Weekly", "Sonnet", "Opus"]
                        let i = Int(idx) % labels.count
                        return i >= 0 ? labels[i] : nil
                    } ?? "Quota",
                    utilization: util,
                    color: color
                )
            }
        } else {
            quotas = []
        }

        todayCost = defaults.double(forKey: "widgetTodayCost")
        todayMessages = defaults.integer(forKey: "widgetTodayMessages")

        if quotas.isEmpty {
            return .placeholder
        }

        return QuotaEntry(
            date: Date(),
            quotas: quotas,
            todayCost: todayCost,
            todayMessages: todayMessages
        )
    }
}

// MARK: - Widget Views

struct QuotaGaugeView: View {
    let quota: QuotaInfo

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(min(quota.utilization, 100) / 100))
                    .stroke(quota.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(quota.utilization))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .frame(width: 36, height: 36)

            Text(quota.label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct ClaudeGodWidgetView: View {
    let entry: QuotaEntry

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("C")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(red: 0.56, green: 0.39, blue: 0.98))
                    )
                Text("Claude God")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if entry.todayCost > 0 {
                    Text(entry.todayCost >= 0.01 ? String(format: "$%.2f", entry.todayCost) : String(format: "$%.3f", entry.todayCost))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 12) {
                ForEach(entry.quotas.prefix(4)) { quota in
                    QuotaGaugeView(quota: quota)
                }
            }
            .frame(maxWidth: .infinity)

            if entry.todayMessages > 0 {
                Text("\(entry.todayMessages) messages today")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }
}

// MARK: - Widget

@main
struct ClaudeGodWidget: Widget {
    let kind = "ClaudeGodWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeGodProvider()) { entry in
            ClaudeGodWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Quotas")
        .description("Monitor your Claude AI quota usage")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
