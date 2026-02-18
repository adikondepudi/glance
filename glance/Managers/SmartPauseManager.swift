import Foundation
import AppKit
import CoreAudio

@MainActor
class SmartPauseManager: ObservableObject {
    static let shared = SmartPauseManager()

    private let settings = AppSettings.shared

    func currentPauseReason() -> String? {
        if settings.detectMeetings && isMeetingActive() {
            return "Meeting or Call"
        }
        if settings.detectScreenRecording && isScreenRecording() {
            return "Screen Recording"
        }
        if settings.detectScreenshots && isScreenshotToolActive() {
            return "Screenshot Tool"
        }
        if settings.detectFullscreenGaming && isFullscreenGameRunning() {
            return "Fullscreen Gaming"
        }
        if settings.detectVideoPlayback && isVideoPlaying() {
            return "Video Playback"
        }
        if isDeepFocusAppActive() {
            return "Deep Focus App"
        }
        return nil
    }

    // MARK: - Screenshot Tool Detection

    private func isScreenshotToolActive() -> Bool {
        let screenshotBundleIDs = [
            "com.apple.Screenshot",           // macOS Screenshot
            "cc.ffitch.shottr",               // Shottr
            "com.cleanshot.CleanShot-X",      // CleanShot X
            "com.monosnap.monosnap",          // Monosnap
        ]

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if screenshotBundleIDs.contains(bundleID) && app.isActive {
                return true
            }
        }
        return false
    }

    // MARK: - Meeting Detection

    private func isMeetingActive() -> Bool {
        return isCameraActive() || isMicrophoneActiveForMeeting()
    }

    private func isCameraActive() -> Bool {
        // Check if any meeting app is running with an active microphone
        // (camera usage implies mic usage in video calls)
        return isAnyMeetingAppRunning() && isMicActive()
    }

    private func isMicrophoneActiveForMeeting() -> Bool {
        guard isAnyMeetingAppRunning() else { return false }
        return isMicActive()
    }

    private func isAnyMeetingAppRunning() -> Bool {
        let meetingBundleIDs = [
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.google.Chrome", // Google Meet runs in Chrome
            "com.apple.FaceTime",
            "com.cisco.webexmeetingsapp",
            "com.slack.Slack",
            "com.discord.Discord",
            "com.skype.skype",
        ]

        let excludedApps = Set(settings.excludedMeetingApps)
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if meetingBundleIDs.contains(bundleID) && !excludedApps.contains(bundleID) {
                if app.isActive || app.ownsMenuBar {
                    return true
                }
            }
        }
        return false
    }

    private func isMicActive() -> Bool {
        let excludedDevices = Set(settings.excludedMicDevices)

        // Get all audio devices
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &dataSize) == noErr else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return false }

        for deviceID in deviceIDs {
            // Skip excluded devices
            if excludedDevices.contains(String(deviceID)) { continue }

            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr else { continue }
            guard inputSize > 0 else { continue }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPtr) == noErr else { continue }

            let bufferList = bufferListPtr.pointee
            guard bufferList.mNumberBuffers > 0, bufferList.mBuffers.mNumberChannels > 0 else { continue }

            // Check if running
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let runStatus = AudioObjectGetPropertyData(
                deviceID,
                &runningAddress,
                0, nil,
                &runningSize,
                &isRunning
            )

            if runStatus == noErr && isRunning != 0 {
                return true
            }
        }

        return false
    }

    // MARK: - Screen Recording Detection

    private func isScreenRecording() -> Bool {
        let recordingBundleIDs = [
            "com.apple.QuickTimePlayerX",
            "com.obsproject.obs-studio",
            "com.loom.desktop",
            "com.techsmith.camtasia",
            "com.kap.Kap",
        ]

        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if recordingBundleIDs.contains(bundleID) {
                return true
            }
        }

        // Also check if CGDisplayStream is capturing (screen sharing)
        if CGMainDisplayID() != 0 {
            // Check for screen capture by looking at the sharing indicator
            // On macOS 12.2+, the system shows an indicator when screen is being shared
            // We detect known sharing apps
            let sharingApps = ["us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2"]
            for app in runningApps {
                guard let bundleID = app.bundleIdentifier else { continue }
                if sharingApps.contains(bundleID) {
                    // If meeting app is active and screen sharing might be on
                    // This is a conservative check
                    break
                }
            }
        }

        return false
    }

    // MARK: - Video Playback Detection

    private func isVideoPlaying() -> Bool {
        let videoApps = [
            "com.apple.QuickTimePlayerX",
            "org.videolan.vlc",
            "com.colliderli.iina",
            "io.mpv",
            "com.apple.TV",
        ]

        let runningApps = NSWorkspace.shared.runningApplications
        let mode = settings.videoPlaybackMode

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if videoApps.contains(bundleID) {
                switch mode {
                case .frontmostOnly:
                    if app.isActive { return true }
                case .background:
                    return true
                }
            }
        }

        // Also check for browser-based video (Netflix, YouTube in fullscreen)
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let browserBundleIDs = [
                "com.apple.Safari",
                "com.google.Chrome",
                "org.mozilla.firefox",
                "com.microsoft.edgemac",
                "com.brave.Browser",
                "company.thebrowser.Browser", // Arc
            ]
            if let bundleID = frontmostApp.bundleIdentifier,
               browserBundleIDs.contains(bundleID) {
                // Check if browser is in fullscreen (likely watching video)
                if isAppInFullscreen(frontmostApp) {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Fullscreen Gaming

    private func isFullscreenGameRunning() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return false }

        // Check if the frontmost app is in fullscreen
        guard isAppInFullscreen(frontmostApp) else { return false }

        // Check if it looks like a game (not a productivity app)
        let knownNonGameFullscreenApps = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.apple.finder",
            "com.apple.Terminal",
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
        ]

        if let bundleID = frontmostApp.bundleIdentifier {
            if knownNonGameFullscreenApps.contains(bundleID) {
                return false
            }
            // Games often have high CPU/GPU usage in fullscreen
            // Simple heuristic: if fullscreen and not a known productivity app, assume game
            if frontmostApp.activationPolicy == .regular {
                return true
            }
        }

        return false
    }

    // MARK: - Deep Focus Apps

    private func isDeepFocusAppActive() -> Bool {
        let focusApps = settings.deepFocusApps
        guard !focusApps.isEmpty else { return false }

        let runningApps = NSWorkspace.shared.runningApplications

        for focusApp in focusApps {
            for app in runningApps {
                guard app.bundleIdentifier == focusApp.bundleIdentifier else { continue }

                switch focusApp.mode {
                case .open:
                    return true
                case .foreground:
                    if app.isActive { return true }
                case .foregroundFullscreen:
                    if app.isActive && isAppInFullscreen(app) { return true }
                }
            }
        }

        return false
    }

    // MARK: - Helpers

    private func isAppInFullscreen(_ app: NSRunningApplication) -> Bool {
        // Check if any window of the app is in fullscreen
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let screenFrame = NSScreen.main?.frame ?? .zero

        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == app.processIdentifier,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowWidth = bounds["Width"],
                  let windowHeight = bounds["Height"] else { continue }

            // Check if window covers the full screen
            if windowWidth >= screenFrame.width && windowHeight >= screenFrame.height {
                return true
            }
        }

        return false
    }
}
