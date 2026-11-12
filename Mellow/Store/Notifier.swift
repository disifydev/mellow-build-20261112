import Foundation
import UserNotifications

/// Локальные уведомления: вечерний итог и письма себе. Разрешение спрашивается только при первом включении.
enum Notifier {
    static let eveningID = "mellow.evening"
    static let enabledKey = "mellow.reminder.enabled"
    static let hourKey = "mellow.reminder.hour"
    static let minuteKey = "mellow.reminder.minute"

    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { done(granted) }
        }
    }

    static func scheduleEvening(hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [eveningID])
        let content = UNMutableNotificationContent()
        content.title = "Mellow"
        content.body = "Как прошёл день? Можно записать итог."
        content.sound = .default
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: eveningID, content: content, trigger: trigger))
    }

    static func cancelEvening() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [eveningID])
    }

    /// Напоминание о письме: без текста письма.
    static func scheduleLetter(id: UUID, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Mellow"
        content.body = "Письмо себе можно открыть."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: letterID(id), content: content, trigger: trigger))
    }

    static func cancelLetter(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [letterID(id)])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func letterID(_ id: UUID) -> String { "mellow.letter.\(id.uuidString)" }
}
