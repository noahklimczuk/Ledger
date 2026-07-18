import Foundation
import SwiftData

/// Lifecycle of a detected recurring series. Replaces the old binary "ignored" flag with a small
/// state machine so low-confidence guesses can be reviewed, dead subscriptions can be surfaced, and
/// the user can pause a series without losing it. `nonisolated` so the off-main detector can read it.
nonisolated enum RecurringStatus: String, Codable, CaseIterable, Sendable {
    /// Detected but not confident enough to trust — awaiting the user's confirm or dismiss.
    case suggested
    /// Confirmed or high-confidence and currently charging. Counts toward totals and the forecast.
    case active
    /// Temporarily not charging, kept for reference (user-set). Out of totals and forecast.
    case paused
    /// Stopped charging past its cadence — likely cancelled. Surfaced so it can be cleaned up.
    case ended
    /// User dismissed it entirely; hidden from totals and forecast.
    case ignored

    var displayName: String {
        switch self {
        case .suggested: "Suggested"
        case .active: "Active"
        case .paused: "Paused"
        case .ended: "Ended"
        case .ignored: "Ignored"
        }
    }
}

/// A recurring charge/income stream auto-detected from transaction history. Persisted (rather than
/// recomputed only in-memory) so the user's review choices stick and forecasting is stable between
/// launches. `RecurringDetectionService` upserts these by `merchantKey`.
///
/// The redesign added a confidence score, a lifecycle (`status`), and amount tracking (`lastAmount`
/// / `baselineAmount`) so the app can review low-confidence guesses, flag price changes, and spot
/// subscriptions that quietly stopped charging. All new fields are defaulted/optional so existing
/// stores migrate automatically.
@Model
final class RecurringSeries {
    /// Normalized merchant string used to match detections across runs.
    @Attribute(.unique) var merchantKey: String
    var displayName: String
    var averageAmount: Decimal
    var cadence: RecurrenceCadence
    var lastOccurrence: Date
    var nextExpected: Date
    var occurrenceCount: Int
    /// Legacy user-dismiss flag. Still honored (it wins over `statusRaw`) so pre-redesign ignore
    /// choices survive migration; new dismissals also set `statusRaw` to `.ignored`.
    var isIgnored: Bool
    var updatedAt: Date

    /// Lifecycle state, stored as a raw string (see `RecurringStatus`). Read through `status`.
    var statusRaw: String = RecurringStatus.active.rawValue
    /// Detection confidence, 0…1: how regular the spacing is, how stable the amount is, and how much
    /// history backs it. Drives whether a detection is trusted (`active`) or needs review (`suggested`).
    var detectionConfidence: Double = 1
    /// First observed occurrence — for "tracking since" and history depth. Nil on migrated rows.
    var firstOccurrence: Date?
    /// Amount of the most recent occurrence. Kept separately from `averageAmount` so a price change
    /// isn't hidden by the running average.
    var lastAmount: Decimal?
    /// Typical amount before the latest occurrence — the baseline a price change is measured against.
    var baselineAmount: Decimal?

    init(
        merchantKey: String,
        displayName: String,
        averageAmount: Decimal,
        cadence: RecurrenceCadence,
        lastOccurrence: Date,
        nextExpected: Date,
        occurrenceCount: Int,
        isIgnored: Bool = false,
        statusRaw: String = RecurringStatus.active.rawValue,
        detectionConfidence: Double = 1,
        firstOccurrence: Date? = nil,
        lastAmount: Decimal? = nil,
        baselineAmount: Decimal? = nil
    ) {
        self.merchantKey = merchantKey
        self.displayName = displayName
        self.averageAmount = averageAmount
        self.cadence = cadence
        self.lastOccurrence = lastOccurrence
        self.nextExpected = nextExpected
        self.occurrenceCount = occurrenceCount
        self.isIgnored = isIgnored
        self.updatedAt = .now
        self.statusRaw = statusRaw
        self.detectionConfidence = detectionConfidence
        self.firstOccurrence = firstOccurrence
        self.lastAmount = lastAmount
        self.baselineAmount = baselineAmount
    }

    var isIncome: Bool { averageAmount > 0 }

    /// Effective lifecycle state. A legacy `isIgnored` wins so pre-redesign dismissals still read as
    /// `.ignored` without a migration script.
    var status: RecurringStatus {
        if isIgnored { return .ignored }
        return RecurringStatus(rawValue: statusRaw) ?? .active
    }

    /// Counts toward the monthly/annual totals and the forecast — only genuinely-live series do.
    var isActive: Bool { status == .active }

    /// Monthly-equivalent magnitude, normalizing the cadence (a weekly charge ≈ 4.3×/mo, a yearly
    /// one ≈ 1/12). Always positive — the sign lives in `isIncome`.
    var monthlyEquivalent: Decimal {
        abs(averageAmount) * Decimal(30.44) / Decimal(cadence.approximateDays)
    }

    /// Annualized magnitude of the series.
    var annualEquivalent: Decimal { monthlyEquivalent * 12 }

    /// The amount to expect for the next charge — the latest observed amount when known (so a recent
    /// price change is reflected), otherwise the running average.
    var predictedAmount: Decimal { lastAmount ?? averageAmount }

    /// Days the next expected charge is overdue (0 if it isn't). The signal behind "likely cancelled".
    func daysOverdue(asOf now: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        guard nextExpected < today else { return 0 }
        return calendar.dateComponents([.day], from: nextExpected, to: today).day ?? 0
    }

    /// The next expected charge date on or after today. A stored `nextExpected` can sit in the recent
    /// past (an active series is kept until it's well overdue), so rolling it forward by whole cadences
    /// keeps the UI from ever showing a "next" date that has already passed, and matches how the
    /// forecast projects upcoming charges.
    func projectedNextDate(asOf now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = nextExpected
        var guardCounter = 0
        while next < today && guardCounter < 60 {
            next = cadence.nextDate(after: next, calendar: calendar)
            guardCounter += 1
        }
        return next
    }

    /// A detected change between the baseline amount and the most recent one, past a meaningful
    /// threshold (>10% and >$1 in magnitude) — nil when the price is effectively steady or unknown.
    var priceChange: PriceChange? {
        guard let last = lastAmount, let base = baselineAmount else { return nil }
        let lastMag = abs(last)
        let baseMag = abs(base)
        guard baseMag > 0 else { return nil }
        let delta = lastMag - baseMag
        guard abs(delta) >= 1, abs(delta) / baseMag >= 0.10 else { return nil }
        return PriceChange(previous: baseMag, current: lastMag)
    }

    struct PriceChange {
        let previous: Decimal
        let current: Decimal
        var delta: Decimal { current - previous }
        var isIncrease: Bool { current > previous }
        /// Fractional change, e.g. 0.2 for a 20% rise.
        var fraction: Double {
            let prev = (previous as NSDecimalNumber).doubleValue
            guard prev != 0 else { return 0 }
            return ((current as NSDecimalNumber).doubleValue - prev) / prev
        }
    }
}
