import Foundation
import SwiftData

/// Persisted per-insight interaction state, keyed by the insight's deterministic `insightId` so a
/// dismissal or snooze survives the weekly regeneration of insights (which recreates the transient
/// `Insight` values from scratch each time).
@Model
final class InsightState {
    @Attribute(.unique) var insightId: String
    var isDismissed: Bool
    var snoozedUntil: Date?
    var firstSeen: Date

    init(insightId: String, isDismissed: Bool = false, snoozedUntil: Date? = nil) {
        self.insightId = insightId
        self.isDismissed = isDismissed
        self.snoozedUntil = snoozedUntil
        self.firstSeen = .now
    }

    /// Hidden if dismissed outright, or still inside its snooze window.
    func isHidden(asOf now: Date) -> Bool {
        if isDismissed { return true }
        if let snoozedUntil, snoozedUntil > now { return true }
        return false
    }
}
