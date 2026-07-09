import Foundation
import SwiftData

/// A user-created bill with an optional recurring cadence and a local-notification reminder.
/// Distinct from `RecurringSeries` (which is auto-detected from history) -- this is something
/// the user explicitly wants to be reminded about.
@Model
final class BillReminder {
    var name: String
    var amount: Decimal
    var dueDate: Date
    /// nil means a one-time bill.
    var cadence: RecurrenceCadence?
    var notifyDaysBefore: Int
    var isEnabled: Bool
    /// Identifier of the pending UNNotificationRequest, so we can update/cancel it.
    var notificationIdentifier: String
    var createdAt: Date

    init(
        name: String,
        amount: Decimal,
        dueDate: Date,
        cadence: RecurrenceCadence? = nil,
        notifyDaysBefore: Int = 1,
        isEnabled: Bool = true
    ) {
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.cadence = cadence
        self.notifyDaysBefore = notifyDaysBefore
        self.isEnabled = isEnabled
        self.notificationIdentifier = UUID().uuidString
        self.createdAt = .now
    }

    var isRecurring: Bool { cadence != nil }

    var isOverdue: Bool { dueDate < Calendar.current.startOfDay(for: .now) }
}
