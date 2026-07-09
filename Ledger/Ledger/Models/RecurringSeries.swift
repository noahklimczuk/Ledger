import Foundation
import SwiftData

/// A recurring charge/income stream auto-detected from transaction history. Persisted (rather
/// than recomputed only in-memory) so the user's ignore choice sticks and forecasting is stable
/// between launches. `RecurringDetectionService` upserts these by `merchantKey`.
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
    var isIgnored: Bool
    var updatedAt: Date

    init(
        merchantKey: String,
        displayName: String,
        averageAmount: Decimal,
        cadence: RecurrenceCadence,
        lastOccurrence: Date,
        nextExpected: Date,
        occurrenceCount: Int,
        isIgnored: Bool = false
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
    }

    var isIncome: Bool { averageAmount > 0 }
}
