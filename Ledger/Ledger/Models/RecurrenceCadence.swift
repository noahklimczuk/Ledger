import Foundation

/// Shared cadence used by both auto-detected recurring series and user-created bill reminders.
/// nonisolated so the off-main sync pipeline (RecurringDetectionService) can call `classify`,
/// `approximateDays`, and `nextDate` — the project defaults types to @MainActor.
nonisolated enum RecurrenceCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        }
    }

    /// Nominal spacing in days, used to classify a detected series from its median gap.
    var approximateDays: Int {
        switch self {
        case .weekly: 7
        case .biweekly: 14
        case .monthly: 30
        case .quarterly: 91
        case .yearly: 365
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        let value: Int
        switch self {
        case .weekly: component = .day; value = 7
        case .biweekly: component = .day; value = 14
        case .monthly: component = .month; value = 1
        case .quarterly: component = .month; value = 3
        case .yearly: component = .year; value = 1
        }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    /// Best-fit cadence for an observed median gap (in days), or nil if it doesn't resemble any.
    static func classify(medianGapDays: Double) -> RecurrenceCadence? {
        let candidates: [(RecurrenceCadence, ClosedRange<Double>)] = [
            (.weekly, 5...9),
            (.biweekly, 12...16),
            (.monthly, 26...33),
            (.quarterly, 84...98),
            (.yearly, 350...380)
        ]
        return candidates.first { $0.1.contains(medianGapDays) }?.0
    }
}
