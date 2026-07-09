import Foundation

enum InsightKind: String, Sendable {
    case trendingCategory
    case budgetOvershoot
    case duplicateSubscription
    case forgottenSubscription
    case largeTransaction
    case leftoverCash
}

enum InsightSeverity: Int, Comparable, Sendable {
    case info = 0
    case notable = 1
    case warning = 2

    static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    var tintHex: String {
        switch self {
        case .info: "#8E8E93"       // gray
        case .notable: "#0A84FF"    // blue
        case .warning: "#FF9F0A"    // orange
        }
    }
}

/// A single, transient on-device insight. Regenerated from current data each time the Insights
/// screen loads; persistence lives only in `InsightState` (dismiss/snooze), matched by `id`.
///
/// `id` must be deterministic and stable for "the same finding" across regenerations, so a user's
/// dismiss/snooze keeps applying. Month-scoped findings embed the month; per-entity findings embed
/// the entity key.
struct Insight: Identifiable, Sendable {
    let id: String
    let kind: InsightKind
    let title: String
    let message: String
    let systemImage: String
    let severity: InsightSeverity
    /// Magnitude used to rank insights of equal severity (typically a dollar amount).
    let rankValue: Double
}
