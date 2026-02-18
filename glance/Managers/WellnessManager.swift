import Foundation
import UserNotifications
import AppKit

@MainActor
class WellnessManager: ObservableObject {
    static let shared = WellnessManager()

    private let settings = AppSettings.shared
    private var blinkTimer: Timer?
    private var postureTimer: Timer?
    private var customReminderTimers: [UUID: Timer] = [:]

    func start() {
        requestNotificationPermission()
        resetTimers()
    }

    func resetTimers() {
        blinkTimer?.invalidate()
        postureTimer?.invalidate()

        if settings.blinkReminderEnabled {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.blinkReminderInterval * 60), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.showBlinkReminder()
                }
            }
        }

        if settings.postureReminderEnabled {
            postureTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.postureReminderInterval * 60), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.showPostureReminder()
                }
            }
        }

        resetCustomReminderTimers()
    }

    // MARK: - Custom Reminders

    func resetCustomReminderTimers() {
        for (_, timer) in customReminderTimers {
            timer.invalidate()
        }
        customReminderTimers.removeAll()

        for reminder in settings.customReminders where reminder.enabled {
            let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(reminder.intervalMinutes * 60), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.showCustomReminder(reminder)
                }
            }
            customReminderTimers[reminder.id] = timer
        }
    }

    private func showCustomReminder(_ reminder: CustomReminder) {
        let title = reminder.name.isEmpty ? "Reminder" : reminder.name
        showNotification(
            title: title,
            body: reminder.message,
            withSound: reminder.soundEnabled
        )
    }

    private func showBlinkReminder() {
        showNotification(
            title: "Blink 👀",
            body: "Remember to blink! Keep your eyes moist and comfortable."
        )
    }

    private func showPostureReminder() {
        showNotification(
            title: "Posture Check 🧘",
            body: "Sit up straight, relax your shoulders, and adjust your screen."
        )
    }

    private func showNotification(title: String, body: String, withSound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if withSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
