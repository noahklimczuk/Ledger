import Foundation

/// The date-range presets offered on the Reports screen, plus a custom start/end.
enum ReportDateRange: String, CaseIterable, Identifiable {
    case thisMonth
    case lastMonth
    case last3Months
    case last6Months
    case thisYear
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .last3Months: "Last 3 Months"
        case .last6Months: "Last 6 Months"
        case .thisYear: "This Year"
        case .custom: "Custom"
        }
    }

    /// Resolves to a concrete interval. `custom` uses the provided bounds (falling back to this month).
    func interval(calendar: Calendar = .current, customStart: Date? = nil, customEnd: Date? = nil, now: Date = .now) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday

        switch self {
        case .thisMonth:
            let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
            return DateInterval(start: monthStart, end: end)
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
            return DateInterval(start: start, end: monthStart)
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: monthStart) ?? monthStart
            let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
            return DateInterval(start: start, end: end)
        case .last6Months:
            let start = calendar.date(byAdding: .month, value: -6, to: monthStart) ?? monthStart
            let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? now
            return DateInterval(start: start, end: end)
        case .thisYear:
            let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? monthStart
            let end = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? now
            return DateInterval(start: yearStart, end: end)
        case .custom:
            let start = customStart.map { calendar.startOfDay(for: $0) } ?? monthStart
            let endDay = customEnd.map { calendar.startOfDay(for: $0) } ?? startOfToday
            // Make the end bound inclusive of the chosen day.
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: max(end, start))
        }
    }
}
