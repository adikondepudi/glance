import Foundation
import SwiftUI
import Combine

// MARK: - Enums

enum SkipDifficulty: String, CaseIterable, Codable {
    case casual = "Casual"
    case balanced = "Balanced"
    case hardcore = "Hardcore"
}

enum MenuBarStyle: String, CaseIterable, Codable {
    case iconOnly = "Icon Only"
    case textOnly = "Text Only"
    case iconAndText = "Icon and Text"
}

enum MenuBarIcon: String, CaseIterable, Codable {
    case eye = "eye"
    case timer = "timer"
    case sparkles = "sparkles"
    case leaf = "leaf"
    case heart = "heart"
    case circle = "circle"
}

enum TimerMode: String, CaseIterable, Codable {
    case interval = "Interval"
    case pomodoro = "Pomodoro"
}

enum LockOnBreakMode: String, CaseIterable, Codable {
    case all = "All Breaks"
    case longOnly = "Long Breaks Only"
    case shortOnly = "Short Breaks Only"
}

enum SmartPauseVideoMode: String, CaseIterable, Codable {
    case frontmostOnly = "Frontmost Only"
    case background = "Running in Background Too"
}

enum DeepFocusMode: String, CaseIterable, Codable {
    case foregroundFullscreen = "Foreground & Fullscreen"
    case foreground = "Foreground"
    case open = "When Open"
}

struct DeepFocusApp: Codable, Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let name: String
    let bundleIdentifier: String
    var mode: DeepFocusMode
}

struct DaySchedule: Codable, Equatable {
    var startHour: Int = 9
    var startMinute: Int = 0
    var endHour: Int = 18
    var endMinute: Int = 0
}

struct OfficeHoursSchedule: Codable {
    var enabled: Bool = false
    var activeDays: Set<Int> = [2, 3, 4, 5, 6] // Mon-Fri (Calendar weekday: Sun=1)
    var startHour: Int = 9
    var startMinute: Int = 0
    var endHour: Int = 18
    var endMinute: Int = 0
    var usePerDaySchedule: Bool = false
    var perDaySchedules: [Int: DaySchedule] = [:] // weekday -> schedule
}

struct AutomationAction: Codable, Identifiable {
    let id: UUID
    var name: String
    var script: String
    var isAppleScript: Bool // true = AppleScript, false = shell
    var trigger: AutomationTrigger
    var enabled: Bool

    enum AutomationTrigger: String, Codable, CaseIterable {
        case breakStart = "Break Start"
        case breakEnd = "Break End"
        case longBreakStart = "Long Break Start"
        case longBreakEnd = "Long Break End"
    }

    init(name: String = "", script: String = "", isAppleScript: Bool = true, trigger: AutomationTrigger = .breakStart, enabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.script = script
        self.isAppleScript = isAppleScript
        self.trigger = trigger
        self.enabled = enabled
    }
}

// MARK: - Settings Manager

class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    // MARK: Break Timing
    @AppStorage("shortBreakInterval") var shortBreakInterval: Int = 20 // minutes
    @AppStorage("shortBreakDuration") var shortBreakDuration: Int = 20 // seconds
    @AppStorage("longBreakEnabled") var longBreakEnabled: Bool = false
    @AppStorage("longBreakInterval") var longBreakInterval: Int = 3 // every N short breaks
    @AppStorage("longBreakDuration") var longBreakDuration: Int = 300 // seconds (5 min)

    // MARK: Timer Mode (Pomodoro)
    @AppStorage("timerModeRaw") var timerModeRaw: String = TimerMode.interval.rawValue
    var timerMode: TimerMode {
        get { TimerMode(rawValue: timerModeRaw) ?? .interval }
        set { timerModeRaw = newValue.rawValue }
    }
    @AppStorage("pomodoroWorkMinutes") var pomodoroWorkMinutes: Int = 25
    @AppStorage("pomodoroShortBreakSeconds") var pomodoroShortBreakSeconds: Int = 300 // 5 min
    @AppStorage("pomodoroLongBreakSeconds") var pomodoroLongBreakSeconds: Int = 900 // 15 min
    @AppStorage("pomodoroLongBreakAfter") var pomodoroLongBreakAfter: Int = 4 // cycles

    // MARK: Skip Behavior
    @AppStorage("skipDifficulty") var skipDifficultyRaw: String = SkipDifficulty.casual.rawValue
    var skipDifficulty: SkipDifficulty {
        get { SkipDifficulty(rawValue: skipDifficultyRaw) ?? .casual }
        set { skipDifficultyRaw = newValue.rawValue }
    }

    // MARK: Postpone Limits
    @AppStorage("maxPostponesPerDay") var maxPostponesPerDay: Int = 0 // 0 = unlimited

    // MARK: Break Options
    @AppStorage("delayWhileTyping") var delayWhileTyping: Bool = true
    @AppStorage("allowEarlyEnd") var allowEarlyEnd: Bool = true
    @AppStorage("earlyEndThreshold") var earlyEndThreshold: Double = 0.7 // 70% through
    @AppStorage("lockOnBreak") var lockOnBreak: Bool = false
    @AppStorage("lockOnBreakModeRaw") var lockOnBreakModeRaw: String = LockOnBreakMode.all.rawValue
    var lockOnBreakMode: LockOnBreakMode {
        get { LockOnBreakMode(rawValue: lockOnBreakModeRaw) ?? .all }
        set { lockOnBreakModeRaw = newValue.rawValue }
    }

    // MARK: Reminders
    @AppStorage("showPreBreakReminder") var showPreBreakReminder: Bool = true
    @AppStorage("preBreakReminderSeconds") var preBreakReminderSeconds: Int = 60
    @AppStorage("reminderVisibleDuration") var reminderVisibleDuration: Int = 10
    @AppStorage("showOvertimeNudge") var showOvertimeNudge: Bool = false
    @AppStorage("overtimeNudgeMinutes") var overtimeNudgeMinutes: Int = 5

    // MARK: Smart Pause
    @AppStorage("detectMeetings") var detectMeetings: Bool = true
    @AppStorage("detectVideoPlayback") var detectVideoPlayback: Bool = true
    @AppStorage("detectScreenshots") var detectScreenshots: Bool = false
    @AppStorage("videoPlaybackModeRaw") var videoPlaybackModeRaw: String = SmartPauseVideoMode.frontmostOnly.rawValue
    var videoPlaybackMode: SmartPauseVideoMode {
        get { SmartPauseVideoMode(rawValue: videoPlaybackModeRaw) ?? .frontmostOnly }
        set { videoPlaybackModeRaw = newValue.rawValue }
    }
    @AppStorage("detectScreenRecording") var detectScreenRecording: Bool = true
    @AppStorage("detectFullscreenGaming") var detectFullscreenGaming: Bool = true
    @AppStorage("smartPauseCooldown") var smartPauseCooldown: Int = 120 // seconds

    // MARK: Idle Detection
    @AppStorage("idleDetectionEnabled") var idleDetectionEnabled: Bool = true
    @AppStorage("idleThresholdSeconds") var idleThresholdSeconds: Int = 120

    // MARK: Wellness
    @AppStorage("blinkReminderEnabled") var blinkReminderEnabled: Bool = false
    @AppStorage("blinkReminderInterval") var blinkReminderInterval: Int = 10 // minutes
    @AppStorage("postureReminderEnabled") var postureReminderEnabled: Bool = false
    @AppStorage("postureReminderInterval") var postureReminderInterval: Int = 30 // minutes
    @AppStorage("resetWellnessAfterBreak") var resetWellnessAfterBreak: Bool = true

    // MARK: Appearance
    @AppStorage("breakBackgroundStyle") var breakBackgroundStyle: String = "gradient" // gradient, solid, image
    @AppStorage("breakGradientStart") var breakGradientStart: String = "#1a1a2e"
    @AppStorage("breakGradientEnd") var breakGradientEnd: String = "#16213e"
    @AppStorage("breakSolidColor") var breakSolidColor: String = "#1a1a2e"
    @AppStorage("breakImagePath") var breakImagePath: String = ""

    // MARK: Sound
    @AppStorage("playSoundOnBreakEnd") var playSoundOnBreakEnd: Bool = true
    @AppStorage("playSoundOnBreakStart") var playSoundOnBreakStart: Bool = false
    @AppStorage("selectedSound") var selectedSound: String = "chime" // built-in name or path
    @AppStorage("soundVolume") var soundVolume: Double = 0.7

    // MARK: Per-Break-Type Sounds
    @AppStorage("soundSettingsMigrated") var soundSettingsMigrated: Bool = false
    @AppStorage("playSoundShortBreakStart") var playSoundShortBreakStart: Bool = false
    @AppStorage("playSoundShortBreakEnd") var playSoundShortBreakEnd: Bool = true
    @AppStorage("playSoundLongBreakStart") var playSoundLongBreakStart: Bool = false
    @AppStorage("playSoundLongBreakEnd") var playSoundLongBreakEnd: Bool = true
    @AppStorage("selectedSoundShortBreakStart") var selectedSoundShortBreakStart: String = "chime"
    @AppStorage("selectedSoundShortBreakEnd") var selectedSoundShortBreakEnd: String = "chime"
    @AppStorage("selectedSoundLongBreakStart") var selectedSoundLongBreakStart: String = "chime"
    @AppStorage("selectedSoundLongBreakEnd") var selectedSoundLongBreakEnd: String = "chime"

    // MARK: General
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("showMenuBarTimer") var showMenuBarTimer: Bool = true
    @AppStorage("showMenuBarIcon") var showMenuBarIcon: Bool = true
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    // askOnIdleReturn removed — idle always silently resets timer

    // MARK: Menu Bar Icon
    @AppStorage("menuBarIconRaw") var menuBarIconRaw: String = MenuBarIcon.eye.rawValue
    var menuBarIcon: MenuBarIcon {
        get { MenuBarIcon(rawValue: menuBarIconRaw) ?? .eye }
        set { menuBarIconRaw = newValue.rawValue }
    }

    // MARK: Wind Down
    @AppStorage("windDownEnabled") var windDownEnabled: Bool = false
    @AppStorage("windDownIntervalMinutes") var windDownIntervalMinutes: Int = 15
    @AppStorage("windDownMessage") var windDownMessageRaw: String = ""
    var windDownMessage: String? {
        get { windDownMessageRaw.isEmpty ? nil : windDownMessageRaw }
        set { windDownMessageRaw = newValue ?? "" }
    }
    @AppStorage("windDownEscalation") var windDownEscalation: Bool = true

    // MARK: Menu Bar Style
    @AppStorage("menuBarStyleRaw") var menuBarStyleRaw: String = MenuBarStyle.iconAndText.rawValue
    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: menuBarStyleRaw) ?? .iconAndText }
        set { menuBarStyleRaw = newValue.rawValue }
    }

    // MARK: Complex Settings (JSON-encoded in UserDefaults)

    var officeHours: OfficeHoursSchedule {
        get {
            guard let data = UserDefaults.standard.data(forKey: "officeHours"),
                  let schedule = try? JSONDecoder().decode(OfficeHoursSchedule.self, from: data) else {
                return OfficeHoursSchedule()
            }
            return schedule
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "officeHours")
            }
            objectWillChange.send()
        }
    }

    var deepFocusApps: [DeepFocusApp] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "deepFocusApps"),
                  let apps = try? JSONDecoder().decode([DeepFocusApp].self, from: data) else {
                return []
            }
            return apps
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "deepFocusApps")
            }
            objectWillChange.send()
        }
    }

    var automations: [AutomationAction] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "automations"),
                  let actions = try? JSONDecoder().decode([AutomationAction].self, from: data) else {
                return []
            }
            return actions
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "automations")
            }
            objectWillChange.send()
        }
    }

    var customMessages: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: "customMessages") ?? [
                "Look at something 20 feet away",
                "Blink and breathe deeply",
                "Stretch your shoulders",
                "Rest your eyes, you deserve it"
            ]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "customMessages")
            objectWillChange.send()
        }
    }

    var excludedMicDevices: [String] {
        get { UserDefaults.standard.stringArray(forKey: "excludedMicDevices") ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: "excludedMicDevices")
            objectWillChange.send()
        }
    }

    var excludedMeetingApps: [String] {
        get { UserDefaults.standard.stringArray(forKey: "excludedMeetingApps") ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: "excludedMeetingApps")
            objectWillChange.send()
        }
    }

    var customReminders: [CustomReminder] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "customReminders"),
                  let reminders = try? JSONDecoder().decode([CustomReminder].self, from: data) else {
                return []
            }
            return reminders
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "customReminders")
            }
            objectWillChange.send()
        }
    }

    var scheduledBreaks: [ScheduledBreak] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "scheduledBreaks"),
                  let breaks = try? JSONDecoder().decode([ScheduledBreak].self, from: data) else {
                return []
            }
            return breaks
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "scheduledBreaks")
            }
            objectWillChange.send()
        }
    }
}
