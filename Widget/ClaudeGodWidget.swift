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
    let lastUpdate: Date?
    let isPlaceholder: Bool

    static let placeholder = QuotaEntry(
        date: Date(),
        quotas: [
            QuotaInfo(label: "Session", utilization: 0, color: .gray),
            QuotaInfo(label: "Weekly", utilization: 0, color: .gray),
            QuotaInfo(label: "Sonnet", utilization: 0, color: .gray),
            QuotaInfo(label: "Opus", utilization: 0, color: .gray)
        ],
        todayCost: 0,
        todayMessages: 0,
        lastUpdate: nil,
        isPlaceholder: true
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

        // Read last update timestamp
        let lastUpdateTS = defaults.double(forKey: "widgetLastUpdate")
        let lastUpdate: Date? = lastUpdateTS > 0 ? Date(timeIntervalSince1970: lastUpdateTS) : nil

        if let data = defaults.data(forKey: "widgetQuotas"),
           let decoded = try? JSONDecoder().decode([[String: Double]].self, from: data) {
            quotas = decoded.map { dict in
                let util = dict["utilization"] ?? 0
                let color: Color = util < 50 ? .green : util < 80 ? .orange : .red
                let labels = ["Session", "Weekly", "Sonnet", "Opus"]
                let label = dict["labelIndex"].flatMap { idx in
                    let i = Int(idx)
                    return i >= 0 && i < labels.count ? labels[i] : nil
                } ?? "Quota"
                return QuotaInfo(label: label, utilization: util, color: color)
            }
        } else {
            quotas = []
        }

        todayCost = defaults.double(forKey: "widgetTodayCost")
        todayMessages = defaults.integer(forKey: "widgetTodayMessages")

        if quotas.isEmpty {
            return QuotaEntry(
                date: Date(),
                quotas: [],
                todayCost: 0,
                todayMessages: 0,
                lastUpdate: nil,
                isPlaceholder: false
            )
        }

        return QuotaEntry(
            date: Date(),
            quotas: quotas,
            todayCost: todayCost,
            todayMessages: todayMessages,
            lastUpdate: lastUpdate,
            isPlaceholder: false
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

    private var staleness: String? {
        guard let lastUpdate = entry.lastUpdate else { return nil }
        let elapsed = Date().timeIntervalSince(lastUpdate)
        if elapsed < 300 { return nil } // Less than 5 min, fresh
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        if hours > 0 { return "\(hours)h ago" }
        return "\(minutes)m ago"
    }

    var body: some View {
        if entry.quotas.isEmpty && !entry.isPlaceholder {
            // No data — prompt user to open the app
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
                }
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                Text("Open app to load data")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(12)
        } else {
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
                    if let stale = staleness {
                        Text(stale)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.orange)
                    } else if entry.todayCost > 0 {
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
