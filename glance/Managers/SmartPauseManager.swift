import Foundation
import AppKit
import CoreMediaIO

@MainActor
class SmartPauseManager: ObservableObject {
    static let shared = SmartPauseManager()

    private let settings = AppSettings.shared

    func currentPauseReason() -> String? {
        let runningApps = NSWorkspace.shared.runningApplications

        if settings.detectMeetings && isMeetingActive(runningApps) {
            return "Meeting or Call"
        }
        if settings.detectScreenRecording && isScreenRecording(runningApps) {
            return "Screen Recording"
        }
        if settings.detectScreenshots && isScreenshotToolActive(runningApps) {
            return "Screenshot Tool"
        }
        if settings.detectFullscreenGaming && isFullscreenGameRunning() {
            return "Fullscreen Gaming"
        }
        if settings.detectVideoPlayback && isVideoPlaying(runningApps) {
            return "Video Playback"
        }
        if isDeepFocusAppActive(runningApps) {
            return "Deep Focus App"
        }
        return nil
    }

    // MARK: - Screenshot Tool Detection

    private func isScreenshotToolActive(_ runningApps: [NSRunningApplication]) -> Bool {
        let screenshotBundleIDs = [
            "com.apple.Screenshot",           // macOS Screenshot
            "cc.ffitch.shottr",               // Shottr
            "com.cleanshot.CleanShot-X",      // CleanShot X
            "com.monosnap.monosnap",          // Monosnap
        ]

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            if screenshotBundleIDs.contains(bundleID) && app.isActive {
                return true
            }
        }
        return false
    }

    // MARK: - Meeting Detection

    private func isMeetingActive(_ runningApps: [NSRunningApplication]) -> Bool {
        return isCameraInUse()
    }

    private func isCameraInUse() -> Bool {
        var property = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, &dataSize) == noErr else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var deviceIDs = [CMIODeviceID](repeating: 0, count: deviceCount)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &property, 0, nil, dataSize, &dataUsed, &deviceIDs) == noErr else { return false }

        for deviceID in deviceIDs {
            // Check if this camera device is actively being used
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningProperty = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )

            var runningUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(deviceID, &runningProperty, 0, nil, runningSize, &runningUsed, &isRunning)

            if status == noErr && isRunning != 0 {
                return true
            }
        }

        return false
    }

    // MARK: - Screen Recording Detection

    private func isScreenRecording(_ runningApps: [NSRunningApplication]) -> Bool {
        let recordingBundleIDs = [
            "com.apple.QuickTimePlayerX",
            "com.obsproject.obs-studio",
            "com.loom.desktop",
            "com.techsmith.camtasia",
            "com.kap.Kap",
        ]

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

    private func isVideoPlaying(_ runningApps: [NSRunningApplication]) -> Bool {
        let videoApps = [
            "com.apple.QuickTimePlayerX",
            "org.videolan.vlc",
            "com.colliderli.iina",
            "io.mpv",
            "com.apple.TV",
        ]

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

    private func isDeepFocusAppActive(_ runningApps: [NSRunningApplication]) -> Bool {
        let focusApps = settings.deepFocusApps
        guard !focusApps.isEmpty else { return false }

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
