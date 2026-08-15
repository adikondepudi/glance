import XCTest
@testable import glance

/// State-machine tests for `BreakManager`.
///
/// These run *hosted* inside the real com.glance.app process (TEST_HOST), so
/// `BreakManager.shared` / `AppSettings.shared` / `StatsManager.shared` are the
/// exact same singletons — and the exact same UserDefaults domain — the
/// developer's installed app uses. Two things make that safe here:
///
/// 1. Every test drives the state machine by calling `tick()` / `breakTick()`
///    (and a couple of other small testing hooks on `BreakManager`) instead of
///    waiting on real timers. `resetForTesting()` also permanently disables
///    BreakManager's own background timers for the process, so there's no
///    race between "the real 1-second timer" and "the test calling tick()
///    manually".
/// 2. `setUp`/`tearDown` snapshot and restore every UserDefaults key a test
///    touches (`UserDefaultsSandbox`), and `StatsManager`'s on-disk
///    persistence is redirected to a scratch directory for the process — so
///    nothing here can leave the developer's real settings or stats history
///    changed after the run.
@MainActor
final class BreakManagerTests: XCTestCase {

    /// Every UserDefaults(.standard) key any test in this file reads or
    /// writes via `AppSettings`.
    private static let settingsKeys: [String] = [
        "shortBreakInterval", "shortBreakDuration",
        "longBreakEnabled", "longBreakInterval", "longBreakDuration",
        "timerModeRaw", "pomodoroWorkMinutes", "pomodoroShortBreakSeconds",
        "pomodoroLongBreakSeconds", "pomodoroLongBreakAfter",
        "skipDifficulty", "maxPostponesPerDay",
        "delayWhileTyping", "lockOnBreak",
        "showPreBreakReminder", "preBreakReminderSeconds",
        "smartPauseCooldown",
        "playSoundOnBreakStart", "playSoundOnBreakEnd",
        "playSoundShortBreakStart", "playSoundShortBreakEnd",
        "playSoundLongBreakStart", "playSoundLongBreakEnd",
        "officeHours", "scheduledBreaks", "automations",
        "hasCompletedOnboarding",
    ]

    /// Redirects StatsManager's on-disk persistence to a per-run scratch
    /// directory exactly once for the whole test process. BreakManager
    /// records a stats event as a side effect of nearly every transition
    /// tested here (break started/completed/skipped/postponed, focus cycle
    /// completed, ...) and StatsManager saves to disk on a real 5s timer, so
    /// without this a slow test run risks overwriting the developer's real
    /// today's-stats JSON file (same com.glance.app Application Support
    /// directory as the installed app).
    private static let redirectStatsToScratch: Void = {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("glanceTests-stats-\(UUID().uuidString)", isDirectory: true)
        StatsManager.statsDirectoryOverrideForTesting = scratch
    }()

    private var sandbox: UserDefaultsSandbox!
    private var settings: AppSettings!
    private var bm: BreakManager!

    override func setUp() {
        super.setUp()
        _ = Self.redirectStatsToScratch

        settings = AppSettings.shared
        sandbox = UserDefaultsSandbox()
        sandbox.track(Self.settingsKeys)

        // Baseline: neutralize everything that would otherwise reach out to
        // the real system (lock the screen, play audible sounds, run the
        // developer's real AppleScript/shell automations, gate ticks behind
        // real office hours / scheduled breaks) or depend on live keyboard
        // activity / wall-clock timing. Individual tests override specific
        // values on top of this as needed.
        settings.longBreakEnabled = false
        settings.timerModeRaw = TimerMode.interval.rawValue
        settings.skipDifficultyRaw = SkipDifficulty.casual.rawValue
        settings.maxPostponesPerDay = 0
        settings.delayWhileTyping = false
        settings.lockOnBreak = false
        settings.showPreBreakReminder = false
        settings.playSoundOnBreakStart = false
        settings.playSoundOnBreakEnd = false
        settings.playSoundShortBreakStart = false
        settings.playSoundShortBreakEnd = false
        settings.playSoundLongBreakStart = false
        settings.playSoundLongBreakEnd = false
        settings.automations = []
        settings.scheduledBreaks = []
        settings.officeHours = OfficeHoursSchedule() // enabled = false
        settings.hasCompletedOnboarding = true

        bm = BreakManager.shared
        bm.resetForTesting()
    }

    override func tearDown() {
        bm.resetForTesting()
        sandbox.restoreAll()
        bm = nil
        settings = nil
        sandbox = nil
        super.tearDown()
    }

    // MARK: - working -> reminding -> onBreak

    func testWorkingToRemindingToOnBreakTransition() {
        settings.shortBreakInterval = 1 // 60s
        settings.showPreBreakReminder = true
        settings.preBreakReminderSeconds = 5
        bm.resetForTesting()

        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, 60)

        for _ in 0..<55 { bm.tick() }
        XCTAssertEqual(bm.state, .reminding, "the pre-break reminder should show once the countdown reaches preBreakReminderSeconds")
        XCTAssertEqual(bm.secondsUntilBreak, 5)

        for _ in 0..<5 { bm.tick() }
        XCTAssertEqual(bm.state, .onBreak(isLong: false), "the countdown reaching zero should start the break")
        XCTAssertEqual(bm.secondsUntilBreak, 0)
    }

    // MARK: - break countdown completing -> working with a fresh interval

    func testBreakCompletingReturnsToWorkingWithFreshInterval() {
        settings.shortBreakInterval = 3 // 180s
        settings.shortBreakDuration = 3 // seconds
        bm.resetForTesting()

        bm.startBreak(isLong: false)
        XCTAssertEqual(bm.state, .onBreak(isLong: false))
        let startingShortBreakCount = bm.shortBreakCount

        bm.breakTick()
        bm.breakTick()
        XCTAssertEqual(bm.state, .onBreak(isLong: false), "shouldn't end before the duration elapses")

        bm.breakTick() // 3rd second reaches shortBreakDuration
        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, settings.shortBreakInterval * 60, "should start a brand-new full interval, not resume a leftover countdown")
        XCTAssertEqual(bm.shortBreakCount, startingShortBreakCount + 1)
    }

    // MARK: - skip honors its limits

    func testSkipBreakHonorsHardcoreDifficulty() {
        settings.shortBreakInterval = 5
        bm.resetForTesting()
        bm.tick()
        let before = bm.secondsUntilBreak

        settings.skipDifficultyRaw = SkipDifficulty.hardcore.rawValue
        bm.skipBreak()
        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, before, "hardcore skip difficulty must block skipping entirely")
        XCTAssertEqual(bm.breaksSkippedCount, 0)

        settings.skipDifficultyRaw = SkipDifficulty.casual.rawValue
        bm.skipBreak()
        XCTAssertEqual(bm.breaksSkippedCount, 1)
        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, settings.shortBreakInterval * 60, "a successful skip resets to a fresh interval")
    }

    func testSkipCurrentBreakHonorsHardcoreDifficulty() {
        settings.shortBreakInterval = 5
        settings.shortBreakDuration = 20
        bm.resetForTesting()

        settings.skipDifficultyRaw = SkipDifficulty.hardcore.rawValue
        bm.startBreak(isLong: false)
        let shortBreakCountBefore = bm.shortBreakCount
        bm.skipBreak() // mid-break skip routes through skipCurrentBreak
        XCTAssertEqual(bm.state, .onBreak(isLong: false), "hardcore should block mid-break skipping too")
        XCTAssertEqual(bm.shortBreakCount, shortBreakCountBefore, "a blocked skip must not end the break")
        XCTAssertEqual(bm.breaksSkippedCount, 0, "a blocked skip must not count either")

        settings.skipDifficultyRaw = SkipDifficulty.casual.rawValue
        bm.skipBreak()
        XCTAssertEqual(bm.state, .working, "a successful mid-break skip ends the break and returns to working")
        XCTAssertEqual(bm.shortBreakCount, shortBreakCountBefore + 1, "the skipped break should still count as completed for cadence purposes")
        // Fixed semantics (was previously dead code): endBreak() no longer
        // unconditionally zeroes breaksSkippedCount out from under a mid-break
        // skip — skipCurrentBreak()'s increment now actually sticks, the same
        // as a before-break skipBreak() increment does.
        XCTAssertEqual(bm.breaksSkippedCount, 1, "a mid-break skip must increment the consecutive-skip streak, not have it immediately reset to 0")
    }

    // MARK: - breaksSkippedCount: pre-break and mid-break skips share semantics

    /// `breaksSkippedCount` is a "consecutive skips in a row" streak (surfaced
    /// in BreakReminderView / BreakOverlayView as "You've skipped N breaks in a
    /// row"). Both skip entry points — `skipBreak()` before a break starts and
    /// `skipCurrentBreak()` mid-break — must contribute to that same streak,
    /// and only an actually-completed break should clear it.
    func testMidBreakSkipAndPreBreakSkipShareConsecutiveSkipStreak() {
        settings.shortBreakInterval = 5
        settings.shortBreakDuration = 20
        bm.resetForTesting()

        bm.skipBreak() // pre-break skip
        XCTAssertEqual(bm.breaksSkippedCount, 1)

        bm.startBreak(isLong: false)
        bm.skipCurrentBreak() // mid-break skip
        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.breaksSkippedCount, 2, "consecutive skips across both skip paths should accumulate")

        bm.startBreak(isLong: false)
        for _ in 0..<20 { bm.breakTick() } // let this one run to completion
        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.breaksSkippedCount, 0, "a break that actually completes (not skipped) should reset the streak")
    }

    // MARK: - postpone honors its limits

    func testPostponeHonorsMaxPerDayLimit() {
        settings.maxPostponesPerDay = 2
        bm.resetForTesting()

        XCTAssertTrue(bm.canPostpone)

        bm.postponeBreak(seconds: 30)
        XCTAssertEqual(bm.postponeCountToday, 1)
        XCTAssertEqual(bm.secondsUntilBreak, 30)
        XCTAssertEqual(bm.state, .working)
        XCTAssertTrue(bm.canPostpone)

        bm.postponeBreak(seconds: 30)
        XCTAssertEqual(bm.postponeCountToday, 2)
        XCTAssertFalse(bm.canPostpone, "should stop allowing postpones once the daily max is reached")
    }

    func testPostponeIsUnlimitedWhenMaxIsZero() {
        settings.maxPostponesPerDay = 0
        bm.resetForTesting()

        for _ in 0..<10 { bm.postponeBreak(seconds: 10) }

        XCTAssertEqual(bm.postponeCountToday, 10)
        XCTAssertTrue(bm.canPostpone, "0 means unlimited postpones regardless of how many were used")
    }

    // MARK: - pause / resume

    func testPauseFreezesCountdownAndResumeReturnsToWorking() {
        settings.shortBreakInterval = 10 // 600s
        settings.smartPauseCooldown = 120
        bm.resetForTesting()

        for _ in 0..<37 { bm.tick() }
        let remainingAtPause = bm.secondsUntilBreak
        XCTAssertEqual(remainingAtPause, 600 - 37)

        bm.pauseByUser()
        XCTAssertEqual(bm.state, .paused)
        XCTAssertTrue(bm.isPausedByUser)
        XCTAssertEqual(bm.secondsUntilBreak, remainingAtPause, "pausing must not itself change the countdown")

        // While paused, ticks are ignored entirely — the countdown stays frozen.
        bm.tick()
        bm.tick()
        XCTAssertEqual(bm.secondsUntilBreak, remainingAtPause, "the countdown must stay frozen for as long as we're paused")

        bm.resumeByUser()
        XCTAssertEqual(bm.state, .working)
        XCTAssertFalse(bm.isPausedByUser)
        // Fixed behavior: resuming a manual pause must restore the countdown
        // that was remaining, not discard it for a brand-new full interval —
        // exactly like resumeFromSmartPause() already does.
        XCTAssertEqual(bm.secondsUntilBreak, remainingAtPause, "resume must preserve the pre-pause countdown, not reset to a fresh interval")

        // The work timer is functional again post-resume.
        bm.tick()
        XCTAssertEqual(bm.secondsUntilBreak, remainingAtPause - 1, "ticks should resume decrementing the countdown after resume")
    }

    // MARK: - manual pause/resume numeric continuity, floored at cooldown

    func testResumeByUserRestoresExactRemainingTimeWhenAboveCooldown() {
        settings.shortBreakInterval = 10 // 600s
        settings.smartPauseCooldown = 120
        bm.resetForTesting()

        for _ in 0..<50 { bm.tick() } // 550 remaining, comfortably above the cooldown
        XCTAssertEqual(bm.secondsUntilBreak, 550)

        bm.pauseByUser()
        XCTAssertEqual(bm.secondsUntilBreak, 550, "pausing must not itself change the countdown")

        bm.resumeByUser()
        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, 550, "plenty of time was left, so it should carry over unchanged")
    }

    func testResumeByUserFloorsRemainingTimeAtCooldown() {
        settings.shortBreakInterval = 10 // 600s
        settings.smartPauseCooldown = 120
        bm.resetForTesting()

        for _ in 0..<595 { bm.tick() } // only 5s remaining, well under the cooldown
        XCTAssertEqual(bm.secondsUntilBreak, 5)

        bm.pauseByUser()
        bm.resumeByUser()

        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, settings.smartPauseCooldown, "should be floored at the cooldown instead of resuming with almost no time left, same as resumeFromSmartPause()")
    }

    // MARK: - smart pause resume, floored at cooldown

    func testSmartPauseResumeKeepsRemainingTimeWhenAboveCooldown() {
        settings.shortBreakInterval = 10 // 600s
        settings.smartPauseCooldown = 120
        bm.resetForTesting()

        for _ in 0..<50 { bm.tick() } // 550 remaining, comfortably above the cooldown
        XCTAssertEqual(bm.secondsUntilBreak, 550)

        bm.enterSmartPause(reason: "Meeting")
        XCTAssertEqual(bm.state, .smartPaused(reason: "Meeting"))
        XCTAssertEqual(bm.secondsUntilBreak, 550, "entering smart pause must not itself change the countdown")

        bm.resumeFromSmartPause()
        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, 550, "plenty of time was left, so it should carry over unchanged")
    }

    func testSmartPauseResumeFloorsRemainingTimeAtCooldown() {
        settings.shortBreakInterval = 10 // 600s
        settings.smartPauseCooldown = 120
        bm.resetForTesting()

        for _ in 0..<595 { bm.tick() } // only 5s remaining, well under the cooldown
        XCTAssertEqual(bm.secondsUntilBreak, 5)

        bm.enterSmartPause(reason: "Meeting")
        bm.resumeFromSmartPause()

        XCTAssertEqual(bm.state, .working)
        XCTAssertEqual(bm.secondsUntilBreak, settings.smartPauseCooldown, "should be floored at the cooldown instead of resuming with almost no time left")
    }

    // MARK: - long-break cadence

    func testLongBreakCadenceEveryNthBreakInIntervalMode() {
        settings.timerModeRaw = TimerMode.interval.rawValue
        settings.longBreakEnabled = true
        settings.longBreakInterval = 3 // every 4th break is long
        bm.resetForTesting()

        var observedIsLong: [Bool] = []
        for _ in 0..<8 {
            bm.startBreakNow()
            guard case .onBreak(let isLong) = bm.state else {
                XCTFail("expected to be on a break")
                return
            }
            observedIsLong.append(isLong)
            bm.endBreak(isLong: isLong)
        }

        XCTAssertEqual(observedIsLong, [false, false, false, true, false, false, false, true])
    }

    func testLongBreakCadenceInPomodoroMode() {
        settings.timerModeRaw = TimerMode.pomodoro.rawValue
        settings.pomodoroLongBreakAfter = 4
        bm.resetForTesting()

        var observedIsLong: [Bool] = []
        for _ in 0..<8 {
            bm.startBreakNow()
            guard case .onBreak(let isLong) = bm.state else {
                XCTFail("expected to be on a break")
                return
            }
            observedIsLong.append(isLong)
            bm.endBreak(isLong: isLong)
        }

        XCTAssertEqual(observedIsLong, [false, false, false, true, false, false, false, true])
        XCTAssertEqual(bm.pomodoroCycle, 8)
    }

    // MARK: - manual break start doesn't stack a second break

    func testStartBreakNowDoesNotStackASecondBreakWhileAlreadyOnBreak() {
        settings.shortBreakDuration = 20
        bm.resetForTesting()

        bm.startBreakNow()
        guard case .onBreak(let isLong) = bm.state else {
            XCTFail("expected to be on a break")
            return
        }

        bm.breakTick()
        bm.breakTick()
        XCTAssertEqual(bm.secondsIntoBreak, 2)

        // A second manual break-start request mid-break must be a no-op.
        bm.startBreakNow()
        XCTAssertEqual(bm.state, .onBreak(isLong: isLong))
        XCTAssertEqual(bm.secondsIntoBreak, 2, "starting a break while already on one must not reset/restack the running break")

        bm.startLongBreakNow()
        XCTAssertEqual(bm.secondsIntoBreak, 2, "startLongBreakNow must also refuse to stack a break on top of a running one")
    }
}
