# Glance

A free, native macOS app that reminds you to take screen breaks. Built with SwiftUI — no Electron, no subscriptions, no telemetry.

Glance lives in your menu bar and gently nudges you to look away from your screen every 20 minutes, following the [20-20-20 rule](https://www.aoa.org/AOA/Images/Patients/Eye%20Conditions/20-20-20-rule.pdf) recommended by eye care professionals.

## Install

1. Download **Glance.dmg** from [Releases](../../releases/latest)
2. Open the DMG and drag Glance to your Applications folder
3. Launch Glance from Applications

> **First launch:** Since Glance is not notarized by Apple, macOS will block it from opening. To allow it:
>
> 1. Open **System Settings** → **Privacy & Security**
> 2. Scroll down to the **Security** section
> 3. Find Glance listed and click **Open Anyway**
> 4. Click **Open** in the confirmation dialog
>
> You only need to do this once. Future launches will work normally.

Glance runs as a menu bar app — look for the icon in the top-right of your screen. There's no dock icon by design.

## Features

**Breaks** — Configurable short breaks (default: every 20 min) and optional long breaks after every N short breaks. Full-screen overlay covers all monitors with a calming background. Pre-break notification gives you a heads-up with options to postpone, skip, or start early.

**Smart Pause** — Automatically pauses when your camera is in use (meetings, video calls), during video playback, screen recording, fullscreen gaming, and any apps you specify. Configurable cooldown after activities end.

**Schedule** — Set active days and hours so you're only reminded during work time. Idle detection resets the timer when you step away, close your laptop lid, or lock your screen.

**Stats** — Track breaks taken, screen time, and screen score. Activity timeline shows your day at a glance — working, breaks, and idle periods.

**Movement Breaks** — Turn long breaks into a chance to get up and move, with prompts to walk, stretch, or refill your water. Verifies you actually stepped away using input idle time — no camera, no tracking, entirely on-device.

**Wellness** — Optional blink and posture reminders via macOS notifications.

**Customization** — Choose break backgrounds (gradients, solid colors, custom images), sounds, custom messages, and skip difficulty (casual, balanced, or hardcore). Option to lock screen on break or delay breaks while typing.

**Automations** — Run AppleScripts or shell commands when breaks start or end. Pause music, change Slack status, enable Do Not Disturb — whatever you want.

**Focus Sync** — Optionally sync breaks to an iOS/macOS Focus mode via Shortcuts, so every Apple device you own reflects break state. See [Sync breaks to your other devices](#sync-breaks-to-your-other-devices-focus) below.

**Keyboard Shortcuts** — `Cmd+Shift+B` to start a break, `Cmd+Shift+P` to pause/resume.

## Sync breaks to your other devices (Focus)

There's no public API for an app to turn Focus on or off directly, so Glance bridges through the Shortcuts app instead. Glance sends the signal ("a break just started/ended"); each device decides what to do with it.

1. Open the **Shortcuts** app and create two shortcuts:
   - **Glance Break Started** — add the **Set Focus** action, set it to turn a Focus **on** (a custom "Break" Focus works well) **until turned off**.
   - **Glance Break Ended** — add **Set Focus**, set it to turn that same Focus **off**.
2. In Glance, open **Settings → General → Focus Sync**, turn on **Sync breaks to a Focus**, and confirm the shortcut names match (defaults are "Glance Break Started" / "Glance Break Ended"). Glance shows a green check next to each name once it finds it in Shortcuts.
3. Use the **Test** button to run the start shortcut, then the end shortcut a few seconds later, so you can confirm the Focus actually toggles before relying on it.

Since Focus state syncs across your Apple devices via iCloud, every signed-in device now knows when you're on a break. From there it's up to you — add per-device **Personal Automations** in Shortcuts that react to the Focus turning on or off, for example:

- **iPhone**: show a calm lock screen, or silence notifications
- **iPad**: open a stretch or breathing app
- **Mac**: pause music, or set a break-themed desktop

Glance never sets Focus directly and never blocks anything on this working — if the shortcut is missing or `shortcuts run` fails, Glance logs it and moves on with the break as normal.

## Updating

Glance checks for updates automatically on launch and periodically in the background. When a new version is available, you'll see a notification with a link to download it.

Your settings and stats are preserved when you update — just replace the app in your Applications folder.

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

The app checks whether your camera is in use to detect meetings, but does not access the camera feed itself.

## License

MIT
