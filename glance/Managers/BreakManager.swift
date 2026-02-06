import Foundation
import Combine
import AppKit

enum BreakState: Equatable {
    case working
    case reminding          // pre-break notification shown
    case countdown(Int)     // countdown to break start (seconds remaining)
    case onBreak(isLong: Bool)
    case paused
    case smartPaused(reason: String)
    case idle
    case outsideSchedule
}

@MainActor
class BreakManager: ObservableObject {
    static let shared = BreakManager()

    @Published var state: BreakState = .working
    @Published var secondsUntilBreak: Int = 0
    @Published var secondsIntoBreak: Int = 0
    @Published var currentBreakDuration: Int = 0
    @Published var shortBreakCount: Int = 0
    @Published var totalScreenTime: TimeInterval = 0
    @Published var isPausedByUser: Bool = false
    @Published var currentMessage: String = ""
    @Published var overtimeSeconds: Int = 0

    private let settings = AppSettings.shared
    private let smartPause = SmartPauseManager.shared
    private let idleDetector = IdleDetector.shared
    private let automation = AutomationManager.shared
    private let sound = SoundManager.shared

    private var workTimer: Timer?
    private var breakTimer: Timer?
    private var overtimeTimer: Timer?
    private var reminderDismissTimer: Timer?
    private var countdownValue: Int = 5
    private var sessionStartDate = Date()
    private var wasSmartPaused = false
    private var smartPauseCooldownTimer: Timer?

    private init() {
        resetWorkTimer()
        startIdleMonitoring()
        startSmartPauseMonitoring()
    }

    // MARK: - Work Timer

    func resetWorkTimer() {
        workTimer?.invalidate()
        overtimeTimer?.invalidate()
        overtimeSeconds = 0
        secondsUntilBreak = settings.shortBreakInterval * 60
        sessionStartDate = Date()
        state = .working

        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.workTimerTick()
            }
        }
    }

    private func workTimerTick() {
        guard state == .working || state == .reminding else { return }

        // Check schedule
        if !isWithinSchedule() {
            state = .outsideSchedule
            workTimer?.invalidate()
            scheduleNextScheduleCheck()
            return
        }

        secondsUntilBreak -= 1
        totalScreenTime += 1

        // Pre-break reminder
        if settings.showPreBreakReminder && secondsUntilBreak == settings.preBreakReminderSeconds && state == .working {
            showPreBreakReminder()
        }

        if secondsUntilBreak <= 0 {
            startBreakSequence()
        }
    }

    // MARK: - Pre-Break Reminder

    private func showPreBreakReminder() {
        state = .reminding
        currentMessage = randomMessage()
        NotificationCenter.default.post(name: .showBreakReminder, object: nil)

        reminderDismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.reminderVisibleDuration), repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.state == .reminding {
                    NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
                    self?.state = .working
                }
            }
        }
    }

    // MARK: - Break Sequence

    private func startBreakSequence() {
        workTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)

        if settings.delayWhileTyping && isUserTyping() {
            // Delay briefly and retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.startBreakSequence()
            }
            return
        }

        // Determine if long break
        let isLong = settings.longBreakEnabled && (shortBreakCount + 1) % settings.longBreakInterval == 0

        countdownValue = 5
        state = .countdown(countdownValue)
        currentMessage = randomMessage()

        NotificationCenter.default.post(name: .showBreakCountdown, object: nil)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                self.countdownValue -= 1
                if self.countdownValue <= 0 {
                    timer.invalidate()
                    self.startBreak(isLong: isLong)
                } else {
                    self.state = .countdown(self.countdownValue)
                }
            }
        }
    }

    func startBreak(isLong: Bool) {
        let duration = isLong ? settings.longBreakDuration : settings.shortBreakDuration
        currentBreakDuration = duration
        secondsIntoBreak = 0
        state = .onBreak(isLong: isLong)

        if settings.playSoundOnBreakStart {
            sound.playBreakSound()
        }

        // Run automations
        let trigger: AutomationAction.AutomationTrigger = isLong ? .longBreakStart : .breakStart
        automation.runAutomations(for: trigger)

        // Lock screen if enabled
        if settings.lockOnBreak {
            lockScreen()
        }

        NotificationCenter.default.post(name: .showBreakOverlay, object: isLong)

        breakTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.breakTimerTick(isLong: isLong)
            }
        }
    }

    private func breakTimerTick(isLong: Bool) {
        secondsIntoBreak += 1

        if secondsIntoBreak >= currentBreakDuration {
            endBreak(isLong: isLong)
        }
    }

    func endBreak(isLong: Bool) {
        breakTimer?.invalidate()

        if settings.playSoundOnBreakEnd {
            sound.playBreakSound()
        }

        let trigger: AutomationAction.AutomationTrigger = isLong ? .longBreakEnd : .breakEnd
        automation.runAutomations(for: trigger)

        shortBreakCount += 1

        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        resetWorkTimer()
    }

    // MARK: - User Actions

    func skipBreak() {
        guard case .countdown = state else { return }
        if settings.skipDifficulty == .hardcore { return }
        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        NotificationCenter.default.post(name: .dismissBreakCountdown, object: nil)
        resetWorkTimer()
    }

    func skipCurrentBreak() {
        guard case .onBreak(let isLong) = state else { return }
        if settings.skipDifficulty == .hardcore { return }
        endBreak(isLong: isLong)
    }

    func endBreakEarly() {
        guard case .onBreak(let isLong) = state else { return }
        guard settings.allowEarlyEnd else { return }
        let progress = Double(secondsIntoBreak) / Double(currentBreakDuration)
        guard progress >= settings.earlyEndThreshold else { return }
        endBreak(isLong: isLong)
    }

    func postponeBreak(seconds: Int) {
        workTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
        NotificationCenter.default.post(name: .dismissBreakCountdown, object: nil)
        secondsUntilBreak = seconds
        state = .working

        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.workTimerTick()
            }
        }
    }

    func startBreakNow() {
        workTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)

        let isLong = settings.longBreakEnabled && (shortBreakCount + 1) % settings.longBreakInterval == 0
        startBreak(isLong: isLong)
    }

    func startLongBreakNow() {
        workTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
        startBreak(isLong: true)
    }

    func pauseByUser() {
        workTimer?.invalidate()
        breakTimer?.invalidate()
        isPausedByUser = true
        state = .paused
        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
    }

    func pauseTemporarily(seconds: Int) {
        pauseByUser()
        Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeByUser()
            }
        }
    }

    func resumeByUser() {
        isPausedByUser = false
        resetWorkTimer()
    }

    // MARK: - Smart Pause

    private func startSmartPauseMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSmartPause()
            }
        }
    }

    private func checkSmartPause() {
        guard !isPausedByUser else { return }
        guard state == .working || state == .reminding || isSmartPaused else { return }

        if let reason = smartPause.currentPauseReason() {
            if !isSmartPaused {
                workTimer?.invalidate()
                NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
                wasSmartPaused = true
            }
            state = .smartPaused(reason: reason)
        } else if isSmartPaused {
            // Activity ended — apply cooldown
            if settings.smartPauseCooldown > 0 && wasSmartPaused {
                wasSmartPaused = false
                secondsUntilBreak = settings.smartPauseCooldown
                state = .working
                workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.workTimerTick()
                    }
                }
            } else {
                resetWorkTimer()
            }
        }
    }

    private var isSmartPaused: Bool {
        if case .smartPaused = state { return true }
        return false
    }

    // MARK: - Idle Detection

    private func startIdleMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdle()
            }
        }
    }

    private func checkIdle() {
        guard settings.idleDetectionEnabled else { return }
        guard state == .working || state == .reminding || state == .idle else { return }

        let idleTime = idleDetector.systemIdleTime
        if idleTime >= TimeInterval(settings.idleThresholdSeconds) {
            if state != .idle {
                workTimer?.invalidate()
                state = .idle
            }
        } else if state == .idle {
            // Returned from idle — reset timer
            resetWorkTimer()
        }
    }

    // MARK: - Schedule

    private func isWithinSchedule() -> Bool {
        let schedule = settings.officeHours
        guard schedule.enabled else { return true }

        let now = Calendar.current.dateComponents([.weekday, .hour, .minute], from: Date())
        guard let weekday = now.weekday, let hour = now.hour, let minute = now.minute else { return true }

        guard schedule.activeDays.contains(weekday) else { return false }

        let currentMinutes = hour * 60 + minute
        let startMinutes = schedule.startHour * 60 + schedule.startMinute
        let endMinutes = schedule.endHour * 60 + schedule.endMinute

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }

    private func scheduleNextScheduleCheck() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isWithinSchedule() == true {
                    self?.resetWorkTimer()
                } else {
                    self?.scheduleNextScheduleCheck()
                }
            }
        }
    }

    // MARK: - Helpers

    private func randomMessage() -> String {
        let messages = settings.customMessages
        return messages.randomElement() ?? "Look away and rest your eyes"
    }

    private func isUserTyping() -> Bool {
        // Check if any key has been pressed recently (last 2 seconds)
        let idleTime = idleDetector.systemIdleTime
        return idleTime < 2
    }

    private func lockScreen() {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    var breakProgress: Double {
        guard currentBreakDuration > 0 else { return 0 }
        return Double(secondsIntoBreak) / Double(currentBreakDuration)
    }

    var canSkip: Bool {
        switch settings.skipDifficulty {
        case .hardcore: return false
        case .balanced:
            if case .onBreak = state {
                return secondsIntoBreak >= 3
            }
            return true
        case .casual: return true
        }
    }

    var canEndEarly: Bool {
        guard settings.allowEarlyEnd else { return false }
        return breakProgress >= settings.earlyEndThreshold
    }

    var formattedTimeUntilBreak: String {
        let mins = secondsUntilBreak / 60
        let secs = secondsUntilBreak % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var formattedBreakTimeRemaining: String {
        let remaining = max(0, currentBreakDuration - secondsIntoBreak)
        let mins = remaining / 60
        let secs = remaining % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        }
        return "\(secs)s"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showBreakReminder = Notification.Name("showBreakReminder")
    static let dismissBreakReminder = Notification.Name("dismissBreakReminder")
    static let showBreakCountdown = Notification.Name("showBreakCountdown")
    static let dismissBreakCountdown = Notification.Name("dismissBreakCountdown")
    static let showBreakOverlay = Notification.Name("showBreakOverlay")
    static let dismissBreakOverlay = Notification.Name("dismissBreakOverlay")
    static let showPostureReminder = Notification.Name("showPostureReminder")
    static let showBlinkReminder = Notification.Name("showBlinkReminder")
}
