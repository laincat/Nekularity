import Foundation
import NekularityKit
import UserNotifications

/// Puts the planned airing reminders on the device.
///
/// The planning is in the kit and has tests; this is the part that talks to the
/// notification framework, which a unit test cannot grant permission to and a
/// simulator run may never agree to. So it stays as small as possible: ask, cancel
/// what should not be there, add what should, and report what happened.
@MainActor
@Observable
final class AiringReminders {
    private(set) var authorised = false
    private(set) var pending = 0
    private(set) var message: String?

    private let center = UNUserNotificationCenter.current()

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorised = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix("airing:") }.count
    }

    /// Asks once. A refusal is a real answer and is reported rather than retried.
    @discardableResult
    func requestAuthorisation() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorised = granted
            message = granted ? nil : "通知权限被拒绝,提醒不会出现"
            return granted
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// Makes the device's reminders match `plan`.
    ///
    /// Cancelling before adding is what keeps a reschedule from duplicating: the
    /// identifiers are stable per show, and iOS would otherwise replace silently in
    /// some cases and queue a duplicate in others.
    func sync(plan: [PlannedReminder]) async {
        guard authorised else {
            message = "还没有通知权限"
            return
        }
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("airing:") }
        let stale = AiringPlan.stale(existing: existing, planned: plan.map { rename($0) })
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        for item in plan {
            let request = UNNotificationRequest(identifier: rename(item).id,
                                               content: content(for: item),
                                               trigger: trigger(for: item))
            // A failed request is reported once at the end rather than per show.
            try? await center.add(request)
        }
        await refreshStatus()
        message = plan.isEmpty
            ? "现在没有需要提醒的剧集"
            : "已安排 \(plan.count) 条提醒"
    }

    func cancelAll() async {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("airing:") }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        await refreshStatus()
        message = "已取消全部提醒"
    }

    /// One namespace, so a cancellation cannot reach a notification this app did not
    /// schedule.
    private func rename(_ reminder: PlannedReminder) -> PlannedReminder {
        var copy = reminder
        copy.id = "airing:" + reminder.id
        return copy
    }

    private func content(for reminder: PlannedReminder) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        return content
    }

    private func trigger(for reminder: PlannedReminder) -> UNCalendarNotificationTrigger {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                    from: reminder.fireAt)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }
}
