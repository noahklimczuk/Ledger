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
}
