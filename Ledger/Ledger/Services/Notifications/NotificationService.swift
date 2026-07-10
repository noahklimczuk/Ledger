import Foundation
import UserNotifications

/// Local-notification scheduling for bill reminders. No server involved -- everything is a
/// `UNCalendarNotificationTrigger` scheduled on-device. One-shot per due date; when a recurring
/// bill is marked paid the view-model advances its due date and reschedules.
@MainActor
enum NotificationService {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func schedule(_ reminder: BillReminder) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminder.notificationIdentifier])

        guard reminder.isEnabled else { return }

        let calendar = Calendar.current
        let fireDay = calendar.date(byAdding: .day, value: -reminder.notifyDaysBefore, to: reminder.dueDate) ?? reminder.dueDate
        var components = calendar.dateComponents([.year, .month, .day], from: fireDay)
        components.hour = 9
        components.minute = 0

        // Don't schedule a notification in the past.
        guard let fireDate = calendar.date(from: components), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming bill: \(reminder.name)"
        content.body = "\(CurrencyFormatter.string(from: reminder.amount)) due \(DateFormatting.medium(reminder.dueDate))"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: reminder.notificationIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancel(_ reminder: BillReminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.notificationIdentifier])
    }

    // MARK: - Immediate delivery (budget guardrails)

    /// Delivers a notification right now. Used by budget guardrails, which decide *when* to fire
    /// themselves (after a sync) rather than scheduling ahead.
    static func deliver(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Quiet authorization for guardrail alerts: if the user hasn't been asked yet, request
    /// provisional access (delivers to Notification Center without an upfront permission prompt).
    /// Returns false only when notifications are explicitly denied.
    static func ensureQuietAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .provisional])) ?? false
        default:
            return true
        }
    }

    // MARK: - Weekly check-in

    static let weeklyCheckInIdentifier = "weekly-check-in"

    /// Repeating reminder for the weekly check-in ritual, Sundays at 6 PM local time.
    static func scheduleWeeklyCheckIn() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [weeklyCheckInIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Weekly Check-In"
        content.body = "Take 2 minutes: review the week's spending, catch any overruns, and zero out your plan."
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1 // Sunday
        components.hour = 18
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyCheckInIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancelWeeklyCheckIn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [weeklyCheckInIdentifier])
    }
}
