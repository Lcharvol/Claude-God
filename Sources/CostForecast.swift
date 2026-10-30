// CostForecast.swift
// End-of-month cost projection from local session history.
//
// Projection = month-to-date spend + recent daily pace × time left in the month.
// Anchoring on actual spend and projecting only the remainder at the recent pace
// keeps one heavy week early in the month from inflating the whole forecast.

import Foundation

enum CostForecast {
    /// Full days before today in the trailing pace window. Seven keeps
    /// weekday/weekend swings averaged out.
    static let paceWindowDays = 7

    struct Projection: Equatable {
        let projected: Double
        let daysRemaining: Int
    }

    /// Projection for the calendar month containing `now`, or nil when there
    /// is no spend this month to project from.
    static func projection(daily: [DailyUsage],
                           now: Date,
                           calendar: Calendar = .current) -> Projection? {
        let today = calendar.startOfDay(for: now)
        guard let month = calendar.dateInterval(of: .month, for: now),
              let paceStart = calendar.date(byAdding: .day, value: -paceWindowDays, to: today)
        else { return nil }

        let costSoFar = cost(of: daily, since: month.start, calendar: calendar)
        guard costSoFar > 0 else { return nil }

        // Elapsed time is fractional so a morning forecast doesn't treat today as
        // a full day. History shorter than the window (new install, pruned logs)
        // shrinks the window rather than diluting the pace with days that have no data.
        let earliestDay = daily.map { calendar.startOfDay(for: $0.date) }.min() ?? today
        let windowStart = max(paceStart, earliestDay)
        let windowDays = days(from: windowStart, to: now)
        guard windowDays > 0 else { return nil }
        let dailyPace = cost(of: daily, since: windowStart, calendar: calendar) / windowDays

        let remainingDays = days(from: now, to: month.end)
        let daysRemaining = calendar.dateComponents([.day], from: today, to: month.end).day.map { $0 - 1 } ?? 0

        return Projection(projected: costSoFar + dailyPace * remainingDays,
                          daysRemaining: max(daysRemaining, 0))
    }

    private static func cost(of daily: [DailyUsage], since start: Date, calendar: Calendar) -> Double {
        daily.filter { calendar.startOfDay(for: $0.date) >= start }.map(\.cost).reduce(0, +)
    }

    private static func days(from start: Date, to end: Date) -> Double {
        max(end.timeIntervalSince(start), 0) / secondsPerDay
    }

    private static let secondsPerDay: TimeInterval = 24 * 3600
}
