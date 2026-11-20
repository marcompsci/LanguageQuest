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

    static let smartPrefix = "lq-smart-"
    static let smartIds = (0..<12).map { smartPrefix + String($0) }

    /// Replaces the player's activity-timed reminders with a new plan (one-shot notifications for the next days).
    static func applySmart(_ plan: [PlannedReminder]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: smartIds)
        for (i, r) in plan.prefix(smartIds.count).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Language Quest"
            content.body = r.body
            content.sound = .default
            content.userInfo = ["template": r.templateId]
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.date)
            center.add(UNNotificationRequest(identifier: smartIds[i], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
    }

    static func removeSmart() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: smartIds) }

    /// Removes every reminder (used when all data is deleted).
    static func removeAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (1...7).map { idPrefix + String($0) } + smartIds)
    }

    /// The template of a reminder the player tapped, waiting for the app to note it (on the device only).
    @MainActor static var openedTemplate: String?
}

/// Notes which reminder was tapped so better messages are chosen more often. Nothing leaves the device.
final class ReminderTapDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderTapDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let t = response.notification.request.content.userInfo["template"] as? String {
            await MainActor.run { ReminderScheduler.openedTemplate = t }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []   // no banners while the app is open
    }
}
