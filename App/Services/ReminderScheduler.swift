import Foundation
import UserNotifications
import LQCore

/// Practice reminders a parent turns on in the parent area. Local notifications only:
/// scheduled on this device, no server, no push token, no tracking.
enum ReminderScheduler {
    static let idPrefix = "lq-practice-"

    /// Asks iOS for permission to show notifications (only when a parent turns reminders on).
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Replaces any scheduled reminders with the plan (or removes them when it's off).
    static func apply(_ plan: ReminderPlan) {
        let center = UNUserNotificationCenter.current()
        let ids = (1...7).map { idPrefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard plan.enabled, plan.isValid else { return }
        for wd in plan.weekdays {
            let content = UNMutableNotificationContent()
            content.title = "Language Quest"
            content.body = ReminderPlan.message(weekday: wd)
            content.sound = .default
            var when = DateComponents()
            when.weekday = wd; when.hour = plan.hour; when.minute = plan.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            center.add(UNNotificationRequest(identifier: idPrefix + String(wd), content: content, trigger: trigger))
        }
    }

    /// Removes every reminder (used when all data is deleted).
    static func removeAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (1...7).map { idPrefix + String($0) })
    }
}
