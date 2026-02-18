# Glance

A free, native macOS app that reminds you to take screen breaks. Built with SwiftUI — no Electron, no subscriptions, no telemetry.

Glance lives in your menu bar and gently nudges you to look away from your screen every 20 minutes, following the [20-20-20 rule](https://www.healthline.com/health/eye-health/20-20-20-rule) recommended by eye care professionals.

## Install

1. Download **Glance.dmg** from [Releases](../../releases/latest)
2. Open the DMG and drag Glance to your Applications folder
3. Launch Glance from Applications

> **First launch:** macOS may show a warning because the app isn't notarized. Right-click the app, click **Open**, then click **Open** again in the dialog. You only need to do this once.

Glance runs as a menu bar app — look for the icon in the top-right of your screen. There's no dock icon by design.

## Features

**Breaks** — Configurable short breaks (default: every 20 min) and optional long breaks. Full-screen overlay covers all monitors with a calming background. Pre-break notification gives you a heads-up with options to postpone, skip, or start early.

**Smart Pause** — Automatically pauses during meetings (detects camera/mic + meeting apps), video playback, screen recording, fullscreen gaming, and any apps you specify. Configurable cooldown after activities end.

**Schedule** — Set active days and hours so you're only reminded during work time. Idle detection auto-pauses when you step away.

**Wellness** — Optional blink and posture reminders via macOS notifications.

**Customization** — Choose break backgrounds (gradients, solid colors, custom images), sounds, custom messages, and skip difficulty (casual, balanced, or hardcore). Option to lock screen on break or delay breaks while typing.

**Automations** — Run AppleScripts or shell commands when breaks start or end. Pause music, change Slack status, enable Do Not Disturb — whatever you want.

**Keyboard Shortcuts** — `Cmd+Shift+B` to start a break, `Cmd+Shift+P` to pause/resume.

## Requirements

macOS 14.0 or later.

## Building from Source

```bash
# Install XcodeGen (first time only)
brew install xcodegen

# Generate Xcode project and build
xcodegen generate
./build.sh
```

To create a distributable DMG:

```bash
# Optional: brew install create-dmg (for a nicer DMG layout)
./release.sh
```

Requires Xcode 15+ with command line tools.

## Permissions

Glance may ask for:

- **Accessibility** — Idle detection and global keyboard shortcuts
- **Notifications** — Wellness reminders (blink, posture)
- **Automation** — Running AppleScripts (only if you use automations)

The app does not access your camera or microphone. It only checks whether they're in use by other apps to detect meetings.

## License

MIT
