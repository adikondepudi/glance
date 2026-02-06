import Foundation
import SwiftUI
import Combine

// MARK: - Enums

enum SkipDifficulty: String, CaseIterable, Codable {
    case casual = "Casual"
    case balanced = "Balanced"
    case hardcore = "Hardcore"
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

struct OfficeHoursSchedule: Codable {
    var enabled: Bool = false
    var activeDays: Set<Int> = [2, 3, 4, 5, 6] // Mon-Fri (Calendar weekday: Sun=1)
    var startHour: Int = 9
    var startMinute: Int = 0
    var endHour: Int = 18
    var endMinute: Int = 0
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

    // MARK: Skip Behavior
    @AppStorage("skipDifficulty") var skipDifficultyRaw: String = SkipDifficulty.casual.rawValue
    var skipDifficulty: SkipDifficulty {
        get { SkipDifficulty(rawValue: skipDifficultyRaw) ?? .casual }
        set { skipDifficultyRaw = newValue.rawValue }
    }

    // MARK: Break Options
    @AppStorage("delayWhileTyping") var delayWhileTyping: Bool = true
    @AppStorage("allowEarlyEnd") var allowEarlyEnd: Bool = true
    @AppStorage("earlyEndThreshold") var earlyEndThreshold: Double = 0.7 // 70% through
    @AppStorage("lockOnBreak") var lockOnBreak: Bool = false

    // MARK: Reminders
    @AppStorage("showPreBreakReminder") var showPreBreakReminder: Bool = true
    @AppStorage("preBreakReminderSeconds") var preBreakReminderSeconds: Int = 60
    @AppStorage("reminderVisibleDuration") var reminderVisibleDuration: Int = 10
    @AppStorage("showFloatingCountdown") var showFloatingCountdown: Bool = true
    @AppStorage("showOvertimeNudge") var showOvertimeNudge: Bool = false
    @AppStorage("overtimeNudgeMinutes") var overtimeNudgeMinutes: Int = 5

    // MARK: Smart Pause
    @AppStorage("detectMeetings") var detectMeetings: Bool = true
    @AppStorage("detectVideoPlayback") var detectVideoPlayback: Bool = true
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

    // MARK: General
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("showMenuBarTimer") var showMenuBarTimer: Bool = true

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
}
