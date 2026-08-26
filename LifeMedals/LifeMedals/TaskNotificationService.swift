import Foundation
import UserNotifications

struct LocalTaskReminder: Sendable {
    let taskID: UUID
    let title: String
    let deadline: Date
}

enum ReminderAuthorizationState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied

    var canSchedule: Bool {
        self == .authorized
    }
}

struct TaskNotificationService: Sendable {
    private static let identifierPrefix = "lifemedals.task."

    @MainActor
    func configureForegroundPresentation() {
        UNUserNotificationCenter.current().delegate = LifeMedalsNotificationDelegate.shared
    }

    func authorizationState() async -> ReminderAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    /// Called from the explicit save action so the system permission prompt has
    /// clear user context. Saving the local task never depends on this result.
    func requestAuthorizationAndSchedule(_ reminder: LocalTaskReminder) async throws -> ReminderAuthorizationState {
        let center = UNUserNotificationCenter.current()
        var state = await authorizationState()

        if state == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
            state = await authorizationState()
        }

        guard state.canSchedule else { return state }
        try await schedule(reminder, with: center)
        return state
    }

    /// Restores future reminders after launch without presenting a permission
    /// prompt. It also clears stale LifeMedals requests while leaving every
    /// notification owned by other apps untouched.
    func synchronize(_ reminders: [LocalTaskReminder]) async throws -> ReminderAuthorizationState {
        let state = await authorizationState()
        guard state.canSchedule else { return state }

        let center = UNUserNotificationCenter.current()
        let activeReminders = reminders.filter { $0.deadline > .now }
        let activeIdentifiers = Set(activeReminders.map(notificationIdentifier(for:)))
        let staleIdentifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !activeIdentifiers.contains($0) }

        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        for reminder in activeReminders {
            try await schedule(reminder, with: center)
        }

        return state
    }

    private func schedule(
        _ reminder: LocalTaskReminder,
        with center: UNUserNotificationCenter
    ) async throws {
        let identifier = notificationIdentifier(for: reminder)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard reminder.deadline > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.text("任务截止提醒")
        content.subtitle = L10n.text(reminder.title)
        content.body = L10n.text("任务契约已到截止时间，回来查看验收标准并提交完成证据。")
        content.sound = .default
        content.userInfo = ["taskID": reminder.taskID.uuidString]

        let dateComponents = Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
            from: reminder.deadline
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    private func notificationIdentifier(for reminder: LocalTaskReminder) -> String {
        Self.identifierPrefix + reminder.taskID.uuidString
    }
}

private final class LifeMedalsNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LifeMedalsNotificationDelegate()

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
