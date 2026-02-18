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
    @Published var secondsSinceLastBreak: Int = 0
    @Published var breaksSkippedCount: Int = 0
    @Published var postponeCountToday: Int = 0
    @Published var pomodoroCycle: Int = 0

    private let settings = AppSettings.shared
    private let smartPause = SmartPauseManager.shared
    private let idleDetector = IdleDetector.shared
    private let automation = AutomationManager.shared
    private let sound = SoundManager.shared
    private let stats = StatsManager.shared

    private var workTimer: Timer?
    private var breakTimer: Timer?
    private var overtimeTimer: Timer?
    private var reminderDismissTimer: Timer?
    private var countdownValue: Int = 5
    private var sessionStartDate = Date()
    private var wasSmartPaused = false
    private var smartPauseCooldownTimer: Timer?
    private var lastResetDate: Date = Date()
    private var previousIdleDuration: TimeInterval = 0
    private var lastTriggeredScheduledBreaks: Set<UUID> = []
    private var lastScheduledBreakCheckMinute: Int = -1
    private var settingsObserver: AnyCancellable?
    private var lastTimerMode: String = ""
    private var lastWorkInterval: Int = 0
    private var lastPomodoroWork: Int = 0

    private init() {
        // Snapshot current settings so we can detect changes
        lastTimerMode = settings.timerModeRaw
        lastWorkInterval = settings.shortBreakInterval
        lastPomodoroWork = settings.pomodoroWorkMinutes

        resetWorkTimer()
        startIdleMonitoring()
        startSmartPauseMonitoring()
        observeSettingsChanges()
    }

    private func observeSettingsChanges() {
        settingsObserver = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Defer to next run loop so the new values are committed
                DispatchQueue.main.async {
                    self?.handleSettingsChanged()
                }
            }
    }

    private func handleSettingsChanged() {
        let newTimerMode = settings.timerModeRaw
        let newWorkInterval = settings.shortBreakInterval
        let newPomodoroWork = settings.pomodoroWorkMinutes

        let modeChanged = newTimerMode != lastTimerMode
        let intervalChanged = newWorkInterval != lastWorkInterval
        let pomodoroChanged = newPomodoroWork != lastPomodoroWork

        lastTimerMode = newTimerMode
        lastWorkInterval = newWorkInterval
        lastPomodoroWork = newPomodoroWork

        // Only reset if we're in the working state and a timing setting actually changed
        guard state == .working || state == .reminding else { return }

        if modeChanged {
            resetWorkTimer()
        } else if settings.timerMode == .pomodoro && pomodoroChanged {
            resetWorkTimer()
        } else if settings.timerMode == .interval && intervalChanged {
            resetWorkTimer()
        }
    }

    // MARK: - Work Timer

    func resetWorkTimer() {
        workTimer?.invalidate()
        overtimeTimer?.invalidate()
        overtimeSeconds = 0

        if settings.timerMode == .pomodoro {
            secondsUntilBreak = settings.pomodoroWorkMinutes * 60
        } else {
            secondsUntilBreak = settings.shortBreakInterval * 60
        }

        sessionStartDate = Date()
        state = .working
        NotificationCenter.default.post(name: .enteredWorkingState, object: nil)

        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.workTimerTick()
            }
        }
    }

    private func workTimerTick() {
        guard state == .working || state == .reminding else { return }

        // Daily reset check
        checkDailyReset()

        // Check schedule
        if !isWithinSchedule() {
            state = .outsideSchedule
            workTimer?.invalidate()
            NotificationCenter.default.post(name: .enteredOutsideSchedule, object: nil)
            scheduleNextScheduleCheck()
            return
        }

        secondsUntilBreak -= 1
        totalScreenTime += 1
        secondsSinceLastBreak += 1

        // Check scheduled breaks
        checkScheduledBreaks()

        // Pre-break reminder
        if settings.showPreBreakReminder && secondsUntilBreak == settings.preBreakReminderSeconds && state == .working {
            showPreBreakReminder()
        }

        if secondsUntilBreak <= 0 {
            startBreakSequence()
        }
    }

    private func checkDailyReset() {
        if !Calendar.current.isDate(lastResetDate, inSameDayAs: Date()) {
            lastResetDate = Date()
            breaksSkippedCount = 0
            postponeCountToday = 0
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
        let isLong: Bool
        if settings.timerMode == .pomodoro {
            isLong = (pomodoroCycle + 1) % settings.pomodoroLongBreakAfter == 0
        } else {
            isLong = settings.longBreakEnabled && (shortBreakCount + 1) % settings.longBreakInterval == 0
        }

        countdownValue = settings.countdownDuration
        state = .countdown(countdownValue)
        currentMessage = randomMessage()

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
        let duration: Int
        if settings.timerMode == .pomodoro {
            duration = isLong ? settings.pomodoroLongBreakSeconds : settings.pomodoroShortBreakSeconds
        } else {
            duration = isLong ? settings.longBreakDuration : settings.shortBreakDuration
        }
        currentBreakDuration = duration
        secondsIntoBreak = 0
        state = .onBreak(isLong: isLong)

        // Per-break-type sounds
        if settings.soundSettingsMigrated {
            let shouldPlay = isLong ? settings.playSoundLongBreakStart : settings.playSoundShortBreakStart
            if shouldPlay {
                let soundName = isLong ? settings.selectedSoundLongBreakStart : settings.selectedSoundShortBreakStart
                sound.playSound(named: soundName)
            }
        } else if settings.playSoundOnBreakStart {
            sound.playBreakSound()
        }

        // Run automations
        let trigger: AutomationAction.AutomationTrigger = isLong ? .longBreakStart : .breakStart
        automation.runAutomations(for: trigger)

        // Lock screen if enabled (with mode check)
        if settings.lockOnBreak {
            let mode = settings.lockOnBreakMode
            let shouldLock = mode == .all || (mode == .longOnly && isLong) || (mode == .shortOnly && !isLong)
            if shouldLock {
                lockScreen()
            }
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

        // Per-break-type sounds
        if settings.soundSettingsMigrated {
            let shouldPlay = isLong ? settings.playSoundLongBreakEnd : settings.playSoundShortBreakEnd
            if shouldPlay {
                let soundName = isLong ? settings.selectedSoundLongBreakEnd : settings.selectedSoundShortBreakEnd
                sound.playSound(named: soundName)
            }
        } else if settings.playSoundOnBreakEnd {
            sound.playBreakSound()
        }

        let trigger: AutomationAction.AutomationTrigger = isLong ? .longBreakEnd : .breakEnd
        automation.runAutomations(for: trigger)

        shortBreakCount += 1
        secondsSinceLastBreak = 0

        // Pomodoro cycle tracking
        if settings.timerMode == .pomodoro {
            pomodoroCycle += 1
            stats.recordFocusCycleCompleted()
        }

        // Stats
        stats.recordBreakCompleted(isLong: isLong)

        // Reset wellness timers after break if enabled
        if settings.resetWellnessAfterBreak {
            WellnessManager.shared.resetTimers()
        }

        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        resetWorkTimer()
    }

    // MARK: - User Actions

    func skipBreak() {
        guard case .countdown = state else { return }
        if settings.skipDifficulty == .hardcore { return }
        breaksSkippedCount += 1
        stats.recordBreakSkipped()
        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        resetWorkTimer()
    }

    func skipCurrentBreak() {
        guard case .onBreak(let isLong) = state else { return }
        if settings.skipDifficulty == .hardcore { return }
        breaksSkippedCount += 1
        stats.recordBreakSkipped()
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
        postponeCountToday += 1
        stats.recordBreakPostponed()
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

    func snoozeBreak(extraSeconds: Int) {
        guard case .onBreak = state else { return }
        currentBreakDuration += extraSeconds
        postponeCountToday += 1
    }

    var canPostpone: Bool {
        let max = settings.maxPostponesPerDay
        if max == 0 { return true } // unlimited
        return postponeCountToday < max
    }

    var formattedTimeSinceLastBreak: String {
        let mins = secondsSinceLastBreak / 60
        if mins < 1 { return "Just started" }
        return "\(mins)m without a break"
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
                previousIdleDuration = 0
                workTimer?.invalidate()
                state = .idle
            }
            previousIdleDuration = idleTime
        } else if state == .idle {
            // Returned from idle
            let breakDuration = Double(settings.shortBreakDuration)
            if settings.askOnIdleReturn && previousIdleDuration >= breakDuration {
                // Show "did you take a break?" prompt
                NotificationCenter.default.post(name: .showIdleReturnPrompt, object: nil)
            }
            resetWorkTimer()
        }
    }

    // MARK: - Scheduled Breaks

    private func checkScheduledBreaks() {
        let scheduled = settings.scheduledBreaks.filter { $0.enabled }
        guard !scheduled.isEmpty else { return }

        let now = Calendar.current.dateComponents([.weekday, .hour, .minute], from: Date())
        guard let weekday = now.weekday, let hour = now.hour, let minute = now.minute else { return }

        let currentMinute = hour * 60 + minute

        // Only check once per minute
        guard currentMinute != lastScheduledBreakCheckMinute else { return }
        lastScheduledBreakCheckMinute = currentMinute

        // Reset triggered set at midnight
        if currentMinute == 0 {
            lastTriggeredScheduledBreaks.removeAll()
        }

        for sb in scheduled {
            let breakMinute = sb.hour * 60 + sb.minute
            guard breakMinute == currentMinute else { continue }
            guard sb.activeDays.contains(weekday) else { continue }
            guard !lastTriggeredScheduledBreaks.contains(sb.id) else { continue }

            lastTriggeredScheduledBreaks.insert(sb.id)
            // Start a break with the scheduled duration
            workTimer?.invalidate()
            reminderDismissTimer?.invalidate()
            NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)

            let isLong = sb.durationSeconds >= 120
            currentBreakDuration = sb.durationSeconds
            secondsIntoBreak = 0
            state = .onBreak(isLong: isLong)
            currentMessage = sb.name.isEmpty ? randomMessage() : sb.name

            NotificationCenter.default.post(name: .showBreakOverlay, object: isLong)

            breakTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.breakTimerTick(isLong: isLong)
                }
            }
            return
        }
    }

    // MARK: - Pomodoro

    var pomodoroLongBreakAfter: Int {
        settings.pomodoroLongBreakAfter
    }

    var formattedPomodoroCycle: String {
        let current = (pomodoroCycle % settings.pomodoroLongBreakAfter) + 1
        return "Cycle \(current)/\(settings.pomodoroLongBreakAfter)"
    }

    // MARK: - Schedule

    private func isWithinSchedule() -> Bool {
        let schedule = settings.officeHours
        guard schedule.enabled else { return true }

        let now = Calendar.current.dateComponents([.weekday, .hour, .minute], from: Date())
        guard let weekday = now.weekday, let hour = now.hour, let minute = now.minute else { return true }

        guard schedule.activeDays.contains(weekday) else { return false }

        let currentMinutes = hour * 60 + minute
        let startMinutes: Int
        let endMinutes: Int

        if schedule.usePerDaySchedule, let daySchedule = schedule.perDaySchedules[weekday] {
            startMinutes = daySchedule.startHour * 60 + daySchedule.startMinute
            endMinutes = daySchedule.endHour * 60 + daySchedule.endMinute
        } else {
            startMinutes = schedule.startHour * 60 + schedule.startMinute
            endMinutes = schedule.endHour * 60 + schedule.endMinute
        }

        // Handle past-midnight schedules (e.g. 22:00 - 02:00)
        if endMinutes <= startMinutes {
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }

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
    static let showBreakOverlay = Notification.Name("showBreakOverlay")
    static let dismissBreakOverlay = Notification.Name("dismissBreakOverlay")
    static let showPostureReminder = Notification.Name("showPostureReminder")
    static let showBlinkReminder = Notification.Name("showBlinkReminder")
    static let showIdleReturnPrompt = Notification.Name("showIdleReturnPrompt")
}
