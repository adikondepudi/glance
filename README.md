# glance

A free, open-source macOS break reminder app that helps reduce eye strain using the 20-20-20 rule. Built with SwiftUI as a native Mac app.

**No licenses. No subscriptions. No telemetry. No bloat.**

## Features

### Core
- **20-20-20 Rule** — Configurable short breaks (default: 20 min work, 20 sec break)
- **Long Breaks** — Optional longer breaks every N short breaks
- **Full-screen Break Overlay** — Covers all screens with a calming display
- **Pre-break Notifications** — Gentle heads-up before breaks with postpone/skip/start-now options
- **Floating Countdown** — A small timer that follows your cursor
- **Menu Bar App** — Live countdown in the menu bar, quick controls in a popover

### Smart Pause
- **Meeting Detection** — Pauses during video calls (detects camera/mic activity + meeting apps)
- **Video Playback Detection** — Pauses during video playback (foreground or background)
- **Screen Recording Detection** — Pauses during screen recording/sharing
- **Fullscreen Gaming Detection** — Pauses when a game is fullscreen
- **Deep Focus Apps** — Add specific apps where breaks should be paused
- **Cooldown Timer** — Configurable delay after an activity ends before breaks resume

### Scheduling
- **Office Hours** — Set active days and time range for break reminders
- **Idle Detection** — Auto-pauses when you're away from the computer

### Wellness
- **Blink Reminders** — Periodic notifications to blink
- **Posture Reminders** — Periodic notifications to check posture
- **Custom Messages** — Write your own break messages in any language

### Customization
- **Skip Difficulty** — Casual (skip anytime), Balanced (delayed skip), Hardcore (no skip)
- **Break Backgrounds** — Gradients, solid colors, or custom images with presets
- **Sounds** — Built-in sounds or custom audio files with volume control
- **Don't Break While Typing** — Delays break until you finish typing
- **Lock Screen on Break** — Optionally lock Mac when break starts
- **End Break Early** — Allow ending break when nearly done

### Automations
- **AppleScript Support** — Run AppleScripts when breaks start or end
- **Shell Scripts** — Run shell commands when breaks start or end
- **Examples included** — Pause Spotify, change Slack status, enable DND, dim screen

### Keyboard Shortcuts
- `Cmd+Shift+B` — Start break now
- `Cmd+Shift+P` — Pause/Resume

### Other
- **Multi-monitor Support** — Break overlay covers all connected screens
- **Launch at Login** — Via SMAppService
- **Fully Native** — Built with SwiftUI + AppKit, no Electron

## Requirements

- macOS 13.0+ (Ventura or later)
- Xcode 15.0+

## Build

```bash
# First time only:
brew install xcodegen

# Generate and build:
xcodegen generate
./build.sh
```

## Architecture

```
glance/
├── App/
│   └── GlanceApp.swift             # Entry point, menu bar, window management
├── Models/
│   └── Settings.swift              # All settings with UserDefaults persistence
├── Managers/
│   ├── BreakManager.swift          # Core state machine and timer logic
│   ├── SmartPauseManager.swift     # Activity detection (meetings, video, gaming)
│   ├── IdleDetector.swift          # System idle time via IOKit
│   ├── AutomationManager.swift     # AppleScript/shell script execution
│   ├── SoundManager.swift          # Sound playback
│   └── WellnessManager.swift       # Posture and blink reminders
├── Views/
│   ├── MenuBarView.swift           # Menu bar popover UI
│   ├── BreakOverlayView.swift      # Full-screen break overlay + window controller
│   ├── BreakReminderView.swift     # Pre-break notification + window controller
│   ├── FloatingCountdownView.swift # Floating countdown + window controller
│   └── Settings/
│       ├── SettingsView.swift      # Tab container
│       ├── GeneralTab.swift        # General settings
│       ├── BreaksTab.swift         # Break timing, skip, messages
│       ├── SmartPauseTab.swift     # Activity detection settings
│       ├── ScheduleTab.swift       # Office hours
│       ├── WellnessTab.swift       # Blink & posture reminders
│       ├── AppearanceTab.swift     # Break backgrounds
│       ├── SoundsTab.swift         # Sound settings
│       └── AutomationTab.swift     # Script automations
├── Info.plist
└── glance.entitlements
```

## Permissions

The app may request:
- **Accessibility** — For idle detection and global keyboard shortcuts
- **Automation** — For running AppleScripts
- **Notifications** — For wellness reminders

The app does **not** use the camera or microphone directly. It only checks if they are in use by other apps (for meeting detection).

## License

MIT
# glance
