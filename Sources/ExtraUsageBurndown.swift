// ExtraUsageBurndown.swift
// Daily spend history for Extra Usage and a burndown chart comparing actual
// month-to-date spend against an even pace toward the monthly limit.
//
// The usage API only reports month-to-date spend, so history is built locally
// from snapshots taken on each refresh (one value per calendar day).

import SwiftUI
import Charts

// MARK: - History (pure)

/// Day key ("yyyy-MM-dd") → month-to-date spend in cents, as last observed that day.
typealias ExtraUsageHistory = [String: Double]

enum ExtraUsageBurndown {
    /// Days of history kept; covers the current and previous month.
    static let retentionDays = 62

    /// Calendar for day keys and month boundaries. Gregorian regardless of the
    /// user's calendar so keys, days of month and billing months always agree.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    static func date(fromDayKey key: String) -> Date? {
        dayKeyFormatter.date(from: key)
    }

    /// History with today's snapshot set to `usedCents` and stale days dropped.
    static func recordedHistory(_ history: ExtraUsageHistory,
                                usedCents: Double,
                                on now: Date,
                                calendar: Calendar = ExtraUsageBurndown.calendar) -> ExtraUsageHistory {
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        let cutoffKey = dayKey(for: cutoff)
        return history
            .filter { $0.key >= cutoffKey }
            .merging([dayKey(for: now): usedCents]) { _, new in new }
    }

    // MARK: Burndown

    struct Point: Identifiable, Equatable {
        let day: Int        // day of month, 1-based
        let cents: Double
        var id: Int { day }
    }

    struct Summary: Equatable {
        let actual: [Point]         // recorded month-to-date spend, by day
        let daysInMonth: Int
        let today: Int              // day of month, 1-based
        let limitCents: Double
        let idealTodayCents: Double // even-pace target at end of today
        let spentCents: Double

        /// Positive = over pace, negative = under pace.
        var deltaCents: Double { spentCents - idealTodayCents }
        var isOverPace: Bool { deltaCents > 0 }

        func idealCents(atDay day: Int) -> Double {
            limitCents * Double(day) / Double(daysInMonth)
        }
    }

    /// Burndown for the current month, when extra usage is enabled with a monthly limit.
    static func summary(for extra: ExtraUsageData?,
                        history: ExtraUsageHistory,
                        now: Date) -> Summary? {
        guard let extra, extra.isEnabled, let limit = extra.monthlyLimit else { return nil }
        return summary(history: history,
                       spentCents: extra.usedCredits ?? 0,
                       limitCents: limit,
                       now: now)
    }

    /// Burndown for the calendar month containing `now`.
    static func summary(history: ExtraUsageHistory,
                        spentCents: Double,
                        limitCents: Double,
                        now: Date,
                        calendar: Calendar = ExtraUsageBurndown.calendar) -> Summary? {
        guard limitCents > 0,
              let monthInterval = calendar.dateInterval(of: .month, for: now),
              let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count else { return nil }

        let today = calendar.component(.day, from: now)
        // Month-to-date spend never decreases, so a recorded value above the live one
        // is stale: typically last month's total captured on the 1st before the API
        // reset `used_credits`. Dropping it avoids a spike on the chart.
        let recorded = history.compactMap { key, cents -> Point? in
            guard let date = date(fromDayKey: key), monthInterval.contains(date) else { return nil }
            return Point(day: calendar.component(.day, from: date), cents: cents)
        }
        .filter { $0.cents <= spentCents }
        // Live value always wins for today; spend starts at zero before day 1.
        let actual = ([Point(day: 0, cents: 0)]
            + recorded.filter { $0.day != today }
            + [Point(day: today, cents: spentCents)])
            .sorted { $0.day < $1.day }

        return Summary(
            actual: actual,
            daysInMonth: daysInMonth,
            today: today,
            limitCents: limitCents,
            idealTodayCents: limitCents * Double(today) / Double(daysInMonth),
            spentCents: spentCents
        )
    }
}

// MARK: - Chart view

struct ExtraUsageBurndownChart: View {
    let summary: ExtraUsageBurndown.Summary

    @Environment(\.textScale) private var textScale

    private static let chartHeight: CGFloat = 70
    private static let axisFontSize: CGFloat = 9

    private var paceColor: Color {
        (summary.isOverPace ? UsageLevel.critical : UsageLevel.good).color
    }

    /// Axis labels can't take `shFont` (they aren't plain views), so scale by hand.
    private var axisFont: Font { .system(size: Self.axisFontSize * textScale) }

    private static func dollars(_ cents: Double) -> String {
        String(format: "$%.2f", cents / 100.0)
    }

    private var paceText: String {
        let amount = Self.dollars(abs(summary.deltaCents))
        return summary.isOverPace ? "\(amount) over" : "\(amount) under"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            chart
                .frame(height: Self.chartHeight)
                .accessibilityHidden(true)

            HStack {
                Text("Pace today")
                    .shFont(11)
                    .foregroundColor(.secondary)
                Spacer()
                Text(paceText)
                    .shFont(11, weight: .semibold, design: .monospaced)
                    .foregroundColor(paceColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Pace today, \(paceText) budget. Target so far \(Self.dollars(summary.idealTodayCents))")
            .help("Even-pace target through today: \(Self.dollars(summary.idealTodayCents)). "
                  + "Assumes the limit resets on the 1st of each calendar month.")
        }
    }

    private var chart: some View {
        Chart {
            // Even-pace line from $0 on day 0 to the limit on the last day
            ForEach([0, summary.daysInMonth], id: \.self) { day in
                LineMark(x: .value("Day", day), y: .value("Spend", summary.idealCents(atDay: day) / 100),
                         series: .value("Series", "Pace"))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(summary.actual) { point in
                AreaMark(x: .value("Day", point.day), y: .value("Spend", point.cents / 100))
                    .foregroundStyle(paceColor.opacity(0.12))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.day), y: .value("Spend", point.cents / 100),
                         series: .value("Series", "Actual"))
                    .foregroundStyle(paceColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }

            RuleMark(x: .value("Today", summary.today))
                .foregroundStyle(Color.secondary.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1))

            PointMark(x: .value("Day", summary.today), y: .value("Spend", summary.spentCents / 100))
                .foregroundStyle(paceColor)
                .symbolSize(20)
        }
        .chartXScale(domain: 0...summary.daysInMonth)
        .chartYScale(domain: 0...max(summary.limitCents, summary.spentCents) / 100)
        .chartXAxis {
            AxisMarks(values: [1, summary.daysInMonth / 2, summary.daysInMonth]) { value in
                // The last day's tick sits on the plot's right edge; a centered label
                // there overflows and Charts drops it. Right-align it so it ends flush
                // with the card's right-aligned values below.
                let isLastDay = value.as(Int.self) == summary.daysInMonth
                AxisValueLabel(anchor: isLastDay ? .topTrailing : .top)
                    .font(axisFont)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let dollars = value.as(Double.self) {
                        Text(String(format: "$%.0f", dollars)).font(axisFont)
                    }
                }
            }
        }
    }
}
