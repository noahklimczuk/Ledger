import Foundation
import UserNotifications

/// Lets local notifications present while the app is foregrounded. Budget guardrail alerts fire
/// from the in-app sync (which only runs while the app is open), so without this delegate they
/// would be delivered silently and never seen.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
