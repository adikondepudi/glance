import Foundation
import Combine
import AppKit
import CoreGraphics
import Darwin

enum BreakState: Equatable {
    case working
    case reminding          // pre-break notification shown
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
    @Published var isMovementBreak: Bool = false
    @Published var secondsSinceLastBreak: Int = 0
    @Published var breaksSkippedCount: Int = 0
    @Published var postponeCountToday: Int = 0
    @Published var pomodoroCycle: Int = 0

    private let settings = AppSettings.shared
    private let smartPause = SmartPauseManager.shared
    private let idleDetector = IdleDetector.shared
    private let automation = AutomationManager.shared
    private let focusBridge = FocusBridgeManager.shared
    private let sound = SoundManager.shared
    private let stats = StatsManager.shared

    private var workTimer: Timer?
    private var breakTimer: Timer?
    private var reminderDismissTimer: Timer?
    private var pauseResumeTimer: Timer?
    private var watchdogTimer: Timer?
    private var typingDelayRetries = 0
    private var sessionStartDate = Date()
    private var wasSmartPaused = false
    private var smartPauseMonitorTimer: Timer?
    private var idleMonitorTimer: Timer?
    private var lastResetDate: Date = Date()
    private var previousIdleDuration: TimeInterval = 0
    private var lastTriggeredScheduledBreaks: Set<UUID> = []
    private var lastScheduledBreakCheckMinute: Int = -1
    private var settingsObserver: AnyCancellable?
    private var lastTimerMode: String = ""
    private var lastWorkInterval: Int = 0
    private var lastPomodoroWork: Int = 0
    // Guards showPreBreakReminder() so it fires once per approach to a break
    // rather than on every tick while secondsUntilBreak <= the lead time.
    private var reminderShownForCurrentCountdown = false

    private init() {
        // Snapshot current settings so we can detect changes
        lastTimerMode = settings.timerModeRaw
        lastWorkInterval = settings.shortBreakInterval
        lastPomodoroWork = settings.pomodoroWorkMinutes

        resetWorkTimer()
        startIdleMonitoring()
        startSmartPauseMonitoring()
        startSystemSleepMonitoring()
        startWatchdog()
        observeSettingsChanges()
        restoreStatsFromDisk()
    }

    // Timers scheduled via Timer.scheduledTimer only fire in the default run loop
    // mode, which pauses while a menu or popover is tracking. Use .common so the
    // countdown never silently stalls.
    private func repeatingTimer(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        // Under unit tests we never want this actually firing on the run loop —
        // tests drive ticks manually via tick()/breakTick() for determinism.
        if !Self.disableAutomaticTimersForTesting {
            RunLoop.main.add(timer, forMode: .common)
        }
        return timer
    }

    private func restoreStatsFromDisk() {
        let today = stats.todayStats
        shortBreakCount = today.breaksCompleted
        totalScreenTime = TimeInterval(today.screenTimeMinutes * 60)
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
        if settings.timerMode == .pomodoro {
            secondsUntilBreak = settings.pomodoroWorkMinutes * 60
        } else {
            secondsUntilBreak = settings.shortBreakInterval * 60
        }
        reminderShownForCurrentCountdown = false

        sessionStartDate = Date()
        state = .working
        NotificationCenter.default.post(name: .enteredWorkingState, object: nil)
        startWorkTimer()
    }

    /// Restarts the 1-second work timer without resetting the countdown.
    private func startWorkTimer() {
        workTimer?.invalidate()
        workTimer = repeatingTimer(every: 1.0) { [weak self] in self?.workTimerTick() }
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

        // Pre-break reminder — fire once we're within the lead time (not just on an
        // exact tick match, which can be skipped by a postpone landing below it),
        // guarded so it doesn't re-fire every second afterward.
        if settings.showPreBreakReminder && !reminderShownForCurrentCountdown
            && secondsUntilBreak <= settings.preBreakReminderSeconds && state == .working {
            reminderShownForCurrentCountdown = true
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

    /// Re-arms the shown-once reminder flag whenever secondsUntilBreak is pushed
    /// back out past the lead time (postpone, smart pause resume) so it shows
    /// again on the way back down. If the new value is still inside (or at) the
    /// lead time, the flag is left untouched: if it was already true (the
    /// reminder was showing and got postponed a short amount) it correctly stays
    /// suppressed, and if it was still false (postponed straight into the lead
    /// window without ever having been shown) the very next tick will show it.
    private func rearmReminderIfBeyondLeadTime(for newSecondsUntilBreak: Int) {
        if newSecondsUntilBreak > settings.preBreakReminderSeconds {
            reminderShownForCurrentCountdown = false
        }
    }

    private func showPreBreakReminder() {
        state = .reminding
        currentMessage = randomMessage()
        NotificationCenter.default.post(name: .showBreakReminder, object: nil)

        // Under unit tests, skip scheduling the auto-dismiss — tests assert the
        // .reminding transition synchronously and don't want a real-time timer
        // flipping state back to .working mid-suite.
        guard !Self.disableAutomaticTimersForTesting else { return }

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

    private func startBreakSequence(isRetry: Bool = false) {
        // A pending retry is only valid while we're still in the limbo it created:
        // if the user paused, went idle, or a fresh work timer is running, abandon it.
        if isRetry {
            guard state == .working || state == .reminding, workTimer?.isValid != true else {
                typingDelayRetries = 0
                return
            }
        }

        workTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)

        if settings.delayWhileTyping && isActiveInputDelayNeeded() && typingDelayRetries < 20 {
            // Delay briefly and retry (capped at ~1 minute of deferral)
            typingDelayRetries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.startBreakSequence(isRetry: true)
            }
            return
        }
        typingDelayRetries = 0

        // Determine if long break
        let isLong: Bool
        if settings.timerMode == .pomodoro {
            isLong = (pomodoroCycle + 1) % settings.pomodoroLongBreakAfter == 0
        } else {
            isLong = settings.longBreakEnabled && (shortBreakCount + 1) % (settings.longBreakInterval + 1) == 0
        }

        currentMessage = randomMessage(isLong: isLong)
        startBreak(isLong: isLong)
    }

    func startBreak(isLong: Bool, durationOverride: Int? = nil) {
        let duration: Int
        if let durationOverride {
            duration = durationOverride
        } else if settings.timerMode == .pomodoro {
            duration = isLong ? settings.pomodoroLongBreakSeconds : settings.pomodoroShortBreakSeconds
        } else {
            duration = isLong ? settings.longBreakDuration : settings.shortBreakDuration
        }
        currentBreakDuration = duration
        secondsIntoBreak = 0
        isMovementBreak = isLong && settings.movementBreaksEnabled
        state = .onBreak(isLong: isLong)

        // Stats: record break started
        stats.recordBreakStarted(isLong: isLong)

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

        // Sync a Focus mode across devices (no-op unless enabled in Settings)
        focusBridge.breakDidStart()

        // Lock screen if enabled (with mode check)
        if settings.lockOnBreak {
            let mode = settings.lockOnBreakMode
            let shouldLock = mode == .all || (mode == .longOnly && isLong) || (mode == .shortOnly && !isLong)
            if shouldLock {
                lockScreen()
            }
        }

        NotificationCenter.default.post(name: .showBreakOverlay, object: isLong)

        breakTimer?.invalidate()
        breakTimer = repeatingTimer(every: 1.0) { [weak self] in self?.breakTimerTick(isLong: isLong) }
    }

    private func breakTimerTick(isLong: Bool) {
        secondsIntoBreak += 1

        if secondsIntoBreak >= currentBreakDuration {
            endBreak(isLong: isLong)
        }
    }

    /// Ends the current break.
    ///
    /// - Parameter wasSkipped: true when this end was triggered by a mid-break
    ///   skip (`skipCurrentBreak()`) rather than the break running its full
    ///   duration (or the watchdog's dead-timer fallback). Skips — pre-break
    ///   via `skipBreak()` or mid-break via `skipCurrentBreak()` — should have
    ///   identical effects on the consecutive-skip streak, so a skip-driven end
    ///   must NOT clear `breaksSkippedCount` the way a genuinely completed
    ///   break does.
    func endBreak(isLong: Bool, wasSkipped: Bool = false) {
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

        // Sync a Focus mode across devices (no-op unless enabled in Settings)
        focusBridge.breakDidEnd()

        shortBreakCount += 1
        secondsSinceLastBreak = 0

        // Pomodoro cycle tracking
        if settings.timerMode == .pomodoro {
            pomodoroCycle += 1
            stats.recordFocusCycleCompleted()
        }

        // Stats
        stats.recordBreakCompleted(isLong: isLong)
        recordMovementVerificationIfNeeded(wasSkipped: wasSkipped)
        isMovementBreak = false

        // Reset consecutive skip counter on a genuinely completed break — but
        // not when this end was itself a skip (see the `wasSkipped` doc above).
        if !wasSkipped {
            breaksSkippedCount = 0
        }

        // Reset wellness timers after break if enabled
        if settings.resetWellnessAfterBreak {
            WellnessManager.shared.resetTimers()
        }

        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        resetWorkTimer()
    }

    // MARK: - User Actions

    func skipBreak() {
        // Mid-break skips must go through skipCurrentBreak so the break timer is stopped
        if case .onBreak = state {
            skipCurrentBreak()
            return
        }
        if settings.skipDifficulty == .hardcore { return }
        reminderDismissTimer?.invalidate()
        breaksSkippedCount += 1
        stats.recordBreakSkipped()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        resetWorkTimer()
    }

    func skipCurrentBreak() {
        guard case .onBreak(let isLong) = state else { return }
        if settings.skipDifficulty == .hardcore { return }
        breaksSkippedCount += 1
        stats.recordBreakSkipped()
        endBreak(isLong: isLong, wasSkipped: true)
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
        rearmReminderIfBeyondLeadTime(for: seconds)
        state = .working
        startWorkTimer()
    }

    func startBreakNow() {
        if case .onBreak = state { return }
        workTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)

        let isLong: Bool
        if settings.timerMode == .pomodoro {
            isLong = (pomodoroCycle + 1) % settings.pomodoroLongBreakAfter == 0
        } else {
            isLong = settings.longBreakEnabled && (shortBreakCount + 1) % (settings.longBreakInterval + 1) == 0
        }
        currentMessage = randomMessage(isLong: isLong)
        startBreak(isLong: isLong)
    }

    func startLongBreakNow() {
        if case .onBreak = state { return }
        workTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
        currentMessage = randomMessage(isLong: true)
        startBreak(isLong: true)
    }

    func pauseByUser() {
        // A manual pause cancels any scheduled auto-resume from pauseTemporarily
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        workTimer?.invalidate()
        breakTimer?.invalidate()
        isPausedByUser = true
        state = .paused
        NotificationCenter.default.post(name: .dismissBreakOverlay, object: nil)
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
    }

    func pauseTemporarily(seconds: Int) {
        pauseByUser()
        guard !Self.disableAutomaticTimersForTesting else { return }
        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeByUser()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseResumeTimer = timer
    }

    /// Resumes from a manual pause with the time that was remaining when
    /// paused, floored at `smartPauseCooldown` — exactly the same "restore,
    /// don't restart" behavior as `resumeFromSmartPause()`. `secondsUntilBreak`
    /// is left untouched by `pauseByUser()`, so it still holds the countdown
    /// from the moment the user paused.
    ///
    /// Unlike `resumeFromSmartPause()`, a manual pause can be entered from
    /// `.outsideSchedule` (smart pause can't — it only triggers from
    /// `.working`/`.reminding`), so this still posts `.enteredWorkingState`
    /// even though it isn't starting a fresh interval: `WindDownManager`
    /// listens for that notification to stop an in-progress wind-down cycle,
    /// and pausing/resuming through an off-hours wind-down must still turn it
    /// off once we're back to working.
    func resumeByUser() {
        guard state == .paused else { return }
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        isPausedByUser = false
        secondsUntilBreak = max(secondsUntilBreak, settings.smartPauseCooldown)
        rearmReminderIfBeyondLeadTime(for: secondsUntilBreak)
        state = .working
        NotificationCenter.default.post(name: .enteredWorkingState, object: nil)
        startWorkTimer()
    }

    func snoozeBreak(extraSeconds: Int) {
        guard case .onBreak = state else { return }
        currentBreakDuration += extraSeconds
        postponeCountToday += 1
        stats.recordBreakPostponed()
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
        smartPauseMonitorTimer?.invalidate()
        smartPauseMonitorTimer = repeatingTimer(every: 5.0) { [weak self] in self?.checkSmartPause() }
    }

    private func checkSmartPause() {
        guard !isPausedByUser else { return }
        guard state == .working || state == .reminding || isSmartPaused else { return }

        if let reason = smartPause.currentPauseReason() {
            enterSmartPause(reason: reason)
        } else if isSmartPaused {
            resumeFromSmartPause()
        }
    }

    /// The "activity detected" half of `checkSmartPause()`, split out so tests
    /// can drive it without depending on the real system checks in
    /// `SmartPauseManager` (meeting/video/recording detection).
    func enterSmartPause(reason: String) {
        if !isSmartPaused {
            workTimer?.invalidate()
            NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
            wasSmartPaused = true
        }
        state = .smartPaused(reason: reason)
    }

    /// The "activity ended" half of `checkSmartPause()` — resume with the time
    /// that was remaining, but leave at least the cooldown so a break doesn't
    /// fire right after a meeting. Split out so tests can drive it directly.
    func resumeFromSmartPause() {
        guard isSmartPaused else { return }
        wasSmartPaused = false
        secondsUntilBreak = max(secondsUntilBreak, settings.smartPauseCooldown)
        rearmReminderIfBeyondLeadTime(for: secondsUntilBreak)
        state = .working
        startWorkTimer()
    }

    private var isSmartPaused: Bool {
        if case .smartPaused = state { return true }
        return false
    }

    // MARK: - Idle Detection

    private func startIdleMonitoring() {
        idleMonitorTimer?.invalidate()
        idleMonitorTimer = repeatingTimer(every: 5.0) { [weak self] in self?.checkIdle() }
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
                stats.recordIdleStarted()
            }
            previousIdleDuration = idleTime
        } else if state == .idle {
            // Returned from idle — silently reset timer
            stats.recordIdleEnded()
            resetWorkTimer()
        }
    }

    // MARK: - System Sleep/Lock Detection

    private func startSystemSleepMonitoring() {
        let workspace = NSWorkspace.shared.notificationCenter

        // Screen off / lid close
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSystemSleep() }
        }

        // System going to sleep
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSystemSleep() }
        }

        // Screen lock
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSystemSleep() }
        }

        // Wake / screen on
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSystemWake() }
        }

        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleSystemWake() }
        }

        // Screen unlock
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSystemWake() }
        }
    }

    private func handleSystemSleep() {
        guard settings.idleDetectionEnabled else { return }
        guard state == .working || state == .reminding else { return }

        workTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)
        previousIdleDuration = 0
        state = .idle
        stats.recordIdleStarted()
    }

    private func handleSystemWake() {
        guard settings.idleDetectionEnabled else { return }
        guard state == .idle else { return }

        stats.recordIdleEnded()
        resetWorkTimer()
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
            // Route through the normal break path so sounds, stats, automations,
            // and lock-on-break all apply to scheduled breaks too
            workTimer?.invalidate()
            reminderDismissTimer?.invalidate()
            NotificationCenter.default.post(name: .dismissBreakReminder, object: nil)

            let isLong = sb.durationSeconds >= 120
            currentMessage = sb.name.isEmpty ? randomMessage(isLong: isLong) : sb.name
            startBreak(isLong: isLong, durationOverride: sb.durationSeconds)
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
        guard !Self.disableAutomaticTimersForTesting else { return }
        let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // If the user paused or started a manual break meanwhile, stop —
                // the normal state transitions take over from there.
                guard self.state == .outsideSchedule else { return }
                if self.isWithinSchedule() {
                    self.resetWorkTimer()
                } else {
                    self.scheduleNextScheduleCheck()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - Watchdog

    // Self-heal: if a state says a timer should be running but it died (e.g. a
    // missed transition or an exception path), restart it instead of staying
    // stuck until the app is relaunched.
    private func startWatchdog() {
        watchdogTimer = repeatingTimer(every: 30) { [weak self] in self?.watchdogCheck() }
    }

    private func watchdogCheck() {
        switch state {
        case .working, .reminding:
            if workTimer?.isValid != true && typingDelayRetries == 0 {
                startWorkTimer()
            }
        case .onBreak(let isLong):
            if breakTimer?.isValid != true {
                endBreak(isLong: isLong)
            }
        case .paused, .smartPaused, .idle, .outsideSchedule:
            break
        }
    }

    // MARK: - Helpers

    /// Built-in prompts shown for a movement long break instead of the
    /// user's normal custom message list — see `randomMessage(isLong:)`.
    private static let movementMessages: [String] = [
        "Walk a loop around your home",
        "Refill your water bottle",
        "10 bodyweight squats",
        "Stretch your hip flexors — deep lunge, each side",
        "Doorway chest stretch",
        "Shoulder rolls and a neck stretch",
        "Step outside for fresh air",
        "Calf raises while you wait",
        "Walk while you take that call",
        "Touch your toes and hang for 30 seconds"
    ]

    /// Picks the message to show for the next break. When `isLong` and
    /// movement breaks are enabled, this draws from the built-in movement
    /// prompt pool instead of the user's custom message list — short breaks
    /// (the default `isLong: false`) and long breaks with the feature off are
    /// untouched.
    private func randomMessage(isLong: Bool = false) -> String {
        if isLong && settings.movementBreaksEnabled {
            return Self.movementMessages.randomElement() ?? "Stand up and move for a few minutes"
        }
        let messages = settings.customMessages
        return messages.randomElement() ?? "Look away and rest your eyes"
    }

    /// How much idle time right at break end is tolerated as "just reaching
    /// back for the mouse/keyboard" rather than proof the user never left —
    /// see `recordMovementVerificationIfNeeded`.
    private static let movementVerificationGraceSeconds: TimeInterval = 15

    /// For a movement long break that just ended, records (via StatsManager)
    /// whether the user actually stepped away.
    ///
    /// Verification is input-idle only, matching the app's no-camera,
    /// on-device privacy stance: if `IdleDetector`'s idle time at break end is
    /// at least the break's total elapsed time minus a ~15s grace period,
    /// there was essentially no keyboard/mouse input for the whole break.
    ///
    /// `secondsIntoBreak` — not `currentBreakDuration` — is used as the
    /// elapsed time. `secondsIntoBreak` is a plain per-second counter that
    /// runs continuously from the moment the break starts; `snoozeBreak(extraSeconds:)`
    /// only raises the `currentBreakDuration` threshold `breakTimerTick`
    /// compares it against, it never resets or otherwise adjusts
    /// `secondsIntoBreak` itself. So whether or not the break was snoozed
    /// mid-way, by the time it ends `secondsIntoBreak` already equals the
    /// true wall-clock time spent on break.
    ///
    /// No-op for short breaks, breaks started while movement breaks are
    /// disabled, and skipped breaks (`wasSkipped`) — a skip isn't "ran to
    /// completion", so there's nothing honest to verify.
    private func recordMovementVerificationIfNeeded(wasSkipped: Bool) {
        guard isMovementBreak, !wasSkipped else { return }

        let elapsed = TimeInterval(secondsIntoBreak)
        let idleTime = idleDetector.systemIdleTime
        let moved = idleTime >= max(0, elapsed - Self.movementVerificationGraceSeconds)

        stats.recordMovementBreak(moved: moved)
        // TODO: garden credit for verified movement once garden merges
    }

    /// The single gate behind `settings.delayWhileTyping`: true if the user is
    /// actively typing, mid-drag, or dictating, in which case
    /// `startBreakSequence` defers rather than interrupting them.
    private func isActiveInputDelayNeeded() -> Bool {
        return isUserTyping() || isUserDragging() || isDictationActive()
    }

    private func isUserTyping() -> Bool {
        // Check if any key has been pressed recently (last 2 seconds)
        let idleTime = idleDetector.systemIdleTime
        return idleTime < 2
    }

    /// True while a mouse button is physically held down (i.e. a drag is in
    /// progress). `CGEventSource.buttonState` reads the hardware button state
    /// directly — unlike a `CGEventTap`, it needs no Accessibility permission
    /// or other entitlement, so this is safe to call unconditionally.
    private func isUserDragging() -> Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
    }

    /// True while macOS Dictation is actively listening. Dictation's
    /// input-method helper, `DictationIM` (`/System/Library/Input
    /// Methods/DictationIM.app`), is registered with launchd as an on-demand
    /// mach service (see its LaunchAgent property list) rather than a
    /// resident daemon — it is absent from the process list at idle and only
    /// appears while a dictation session is actually active. That makes it a
    /// signal specific to Dictation, unlike raw microphone-in-use (already
    /// used for meeting detection in `SmartPauseManager`), which would
    /// otherwise be indistinguishable from a call.
    private func isDictationActive() -> Bool {
        runningProcessNames().contains("DictationIM")
    }

    /// Enumerates current process names via `sysctl(KERN_PROC_ALL)` — the
    /// same permissionless mechanism `ps`/`top` use to list every process on
    /// the system, requiring no entitlements or permission prompts.
    private func runningProcessNames() -> Set<String> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, u_int(mib.count), &procList, &size, nil, 0) == 0 else { return [] }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        var names = Set<String>()
        names.reserveCapacity(actualCount)
        for i in 0..<actualCount {
            let comm = procList[i].kp_proc.p_comm
            let name = withUnsafeBytes(of: comm) { rawBuffer -> String in
                let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self)
                return String(cString: ptr)
            }
            names.insert(name)
        }
        return names
    }

    private func lockScreen() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            // Intentional: lock screen is best-effort
        }
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

    // MARK: - Testing Support
    //
    // These hooks exist so glanceTests can drive the state machine
    // deterministically — never sleeping on real wall-clock timers and never
    // racing the shared instance's own background timers. They have no effect
    // on the shipped app: `disableAutomaticTimersForTesting` defaults to false
    // and every other helper here just re-exposes existing private logic.

    /// When true, none of BreakManager's periodic/delayed timers are actually
    /// scheduled on the run loop — callers must drive ticks manually via
    /// `tick()` / `breakTick()`. Only ever set by test code.
    static var disableAutomaticTimersForTesting = false

    /// Stops every timer owned by the shared instance and restores a clean
    /// `.working` state based on current settings, so each test starts from a
    /// known, deterministic baseline. Also flips
    /// `disableAutomaticTimersForTesting` on for the remainder of the process.
    func resetForTesting() {
        Self.disableAutomaticTimersForTesting = true

        workTimer?.invalidate()
        breakTimer?.invalidate()
        reminderDismissTimer?.invalidate()
        pauseResumeTimer?.invalidate()
        watchdogTimer?.invalidate()
        smartPauseMonitorTimer?.invalidate()
        idleMonitorTimer?.invalidate()

        typingDelayRetries = 0
        wasSmartPaused = false
        isPausedByUser = false
        isMovementBreak = false
        breaksSkippedCount = 0
        postponeCountToday = 0
        pomodoroCycle = 0
        shortBreakCount = 0
        secondsSinceLastBreak = 0
        lastTriggeredScheduledBreaks.removeAll()
        lastScheduledBreakCheckMinute = -1

        resetWorkTimer()
    }

    /// Advances the work/reminder countdown by one simulated second — the same
    /// logic the real 1-second work timer calls in production.
    func tick() {
        workTimerTick()
    }

    /// Advances the break countdown by one simulated second, if currently on a
    /// break — the same logic the real 1-second break timer calls in
    /// production. No-op otherwise.
    func breakTick() {
        guard case .onBreak(let isLong) = state else { return }
        breakTimerTick(isLong: isLong)
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
    static let dismissPopover = Notification.Name("dismissPopover")
}
