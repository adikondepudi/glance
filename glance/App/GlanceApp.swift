import SwiftUI
import AppKit

@main
struct GlanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var breakWindowControllers: [BreakWindowController] = []
    private var windDownWindowControllers: [WindDownWindowController] = []
    private var reminderWindow: ReminderWindowController?
    private var onboardingWindow: NSWindow?
    private let breakManager = BreakManager.shared
    private let wellness = WellnessManager.shared
    private let windDown = WindDownManager.shared
    private let stats = StatsManager.shared
    private let settings = AppSettings.shared
    private var eventMonitor: Any?
    private var clickMonitor: Any?
    private var escapeMonitor: Any?
    private var menuBarTimer: Timer?
    private var lastEscapeTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupNotificationObservers()
        setupSettingsWindowObserver()
        wellness.start()
        windDown.start()
        setupGlobalShortcuts()
        migrateSoundSettings()

        // Onboarding (#11)
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stats.saveNow()
    }

    // MARK: - Sound Settings Migration

    private func migrateSoundSettings() {
        guard !settings.soundSettingsMigrated else { return }
        settings.playSoundShortBreakStart = settings.playSoundOnBreakStart
        settings.playSoundShortBreakEnd = settings.playSoundOnBreakEnd
        settings.playSoundLongBreakStart = settings.playSoundOnBreakStart
        settings.playSoundLongBreakEnd = settings.playSoundOnBreakEnd
        settings.selectedSoundShortBreakStart = settings.selectedSound
        settings.selectedSoundShortBreakEnd = settings.selectedSound
        settings.selectedSoundLongBreakStart = settings.selectedSound
        settings.selectedSoundLongBreakEnd = settings.selectedSound
        settings.soundSettingsMigrated = true
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let iconName = settings.menuBarIcon.rawValue
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "glance")
            button.image?.size = NSSize(width: 16, height: 16)
            button.imagePosition = .imageLeading
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(breakManager)
                .environmentObject(AppSettings.shared)
        )

        // Update menu bar timer
        menuBarTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarTitle()
            }
        }
    }

    @MainActor
    private func updateMenuBarTitle() {
        let style = settings.menuBarStyle
        let iconName = settings.menuBarIcon.rawValue

        // Icon visibility (#8, #15)
        if style == .textOnly || !settings.showMenuBarIcon {
            statusItem.button?.image = nil
        } else {
            let img = NSImage(systemSymbolName: iconName, accessibilityDescription: "glance")
            img?.size = NSSize(width: 16, height: 16)
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeading
        }

        // Text visibility (#15)
        if style == .iconOnly {
            statusItem.button?.title = ""
            return
        }

        guard settings.showMenuBarTimer else {
            statusItem.button?.title = ""
            return
        }

        switch breakManager.state {
        case .working, .reminding:
            statusItem.button?.title = " \(breakManager.formattedTimeUntilBreak)"
        case .onBreak:
            statusItem.button?.title = " Break"
        case .paused:
            statusItem.button?.title = " Paused"
        case .smartPaused(let reason):
            statusItem.button?.title = " \(reason)"
        case .idle:
            statusItem.button?.title = " Idle"
        case .outsideSchedule:
            statusItem.button?.title = " Off"
        }
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Start Break", action: #selector(contextStartBreak), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Check pause state on main actor
        let isPaused = MainActor.assumeIsolated { breakManager.isPausedByUser }
        if isPaused {
            menu.addItem(NSMenuItem(title: "Resume", action: #selector(contextResume), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Pause", action: #selector(contextPause), keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(contextCheckForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(contextOpenSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Glance", action: #selector(contextQuit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func contextStartBreak() {
        Task { @MainActor in breakManager.startBreakNow() }
    }

    @objc private func contextPause() {
        Task { @MainActor in breakManager.pauseByUser() }
    }

    @objc private func contextResume() {
        Task { @MainActor in breakManager.resumeByUser() }
    }

    @objc private func contextCheckForUpdates() {
        Task { @MainActor in
            UpdateManager.shared.checkForUpdates { [weak self] state in
                self?.showUpdateAlert(state)
            }
        }
    }

    @MainActor private func showUpdateAlert(_ state: UpdateCheckState) {
        let alert = NSAlert()
        switch state {
        case .upToDate:
            alert.messageText = "You're up to date"
            alert.informativeText = "Glance \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") is the latest version."
            alert.alertStyle = .informational
        case .available(let version):
            alert.messageText = "Update Available"
            alert.informativeText = "Glance \(version) is available."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .informational
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                UpdateManager.shared.openReleasePage()
            }
            return
        case .error:
            alert.messageText = "Update Check Failed"
            alert.informativeText = "Could not check for updates. Please try again later."
            alert.alertStyle = .warning
        default:
            return
        }
        alert.runModal()
    }

    @objc private func contextOpenSettings() {
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupSettingsWindowObserver() {
        // No-op: app stays as accessory (no dock icon) at all times
    }

    @objc private func contextQuit() {
        NSApp.terminate(nil)
    }

    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                closePopover()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
                startClickMonitor()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        stopClickMonitor()
    }

    private func startClickMonitor() {
        stopClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true {
                self?.closePopover()
            }
        }
    }

    private func stopClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissPopover), name: .dismissPopover, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowBreakOverlay(_:)), name: .showBreakOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissBreakOverlay), name: .dismissBreakOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowBreakReminder), name: .showBreakReminder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissBreakReminder), name: .dismissBreakReminder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowWindDown), name: .showWindDownOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissWindDown), name: .dismissWindDownOverlay, object: nil)
    }

    @objc private func handleDismissPopover() {
        closePopover()
    }

    @objc private func handleShowBreakOverlay(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.showBreakOverlay()
        }
    }

    @objc private func handleDismissBreakOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.dismissBreakOverlay()
        }
    }

    @objc private func handleShowBreakReminder() {
        DispatchQueue.main.async { [weak self] in
            self?.showReminderWindow()
        }
    }

    @objc private func handleDismissBreakReminder() {
        DispatchQueue.main.async { [weak self] in
            self?.dismissReminderWindow()
        }
    }

    // MARK: - Wind Down Overlay

    @objc private func handleShowWindDown() {
        DispatchQueue.main.async { [weak self] in
            self?.showWindDownOverlay()
        }
    }

    @objc private func handleDismissWindDown() {
        DispatchQueue.main.async { [weak self] in
            self?.dismissWindDownOverlay()
        }
    }

    private func showWindDownOverlay() {
        dismissWindDownOverlay()
        for screen in NSScreen.screens {
            let controller = WindDownWindowController(screen: screen)
            controller.showWindow(nil)
            windDownWindowControllers.append(controller)
        }
    }

    private func dismissWindDownOverlay() {
        for controller in windDownWindowControllers {
            controller.close()
        }
        windDownWindowControllers.removeAll()
    }

    // MARK: - Break Overlay (all screens)

    private func showBreakOverlay() {
        dismissBreakOverlay()

        for screen in NSScreen.screens {
            let controller = BreakWindowController(screen: screen)
            controller.showWindow(nil)
            breakWindowControllers.append(controller)
        }

        // Double-escape to skip (#4)
        installEscapeMonitor()
    }

    private func dismissBreakOverlay() {
        for controller in breakWindowControllers {
            controller.close()
        }
        breakWindowControllers.removeAll()
        removeEscapeMonitor()
    }

    // MARK: - Double Escape (#4)

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = Escape
            let now = Date()
            if let last = self?.lastEscapeTime, now.timeIntervalSince(last) < 1.0 {
                // Double escape detected
                Task { @MainActor in
                    self?.breakManager.skipCurrentBreak()
                }
                self?.lastEscapeTime = nil
            } else {
                self?.lastEscapeTime = now
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        lastEscapeTime = nil
    }

    // MARK: - Reminder Window

    private func showReminderWindow() {
        dismissReminderWindow()
        reminderWindow = ReminderWindowController()
        reminderWindow?.showWindow(nil)
    }

    private func dismissReminderWindow() {
        reminderWindow?.close()
        reminderWindow = nil
    }

    // MARK: - Global Shortcuts

    private func setupGlobalShortcuts() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .shift]) else { return }

            Task { @MainActor in
                switch event.keyCode {
                case 11: // B key
                    self?.breakManager.startBreakNow()
                case 35: // P key
                    if self?.breakManager.isPausedByUser == true {
                        self?.breakManager.resumeByUser()
                    } else {
                        self?.breakManager.pauseByUser()
                    }
                case 37: // L key — Start long break now (#14)
                    self?.breakManager.startLongBreakNow()
                case 18: // 1 key — Postpone 1 minute (#14)
                    self?.breakManager.postponeBreak(seconds: 60)
                case 23: // 5 key — Postpone 5 minutes (#14)
                    self?.breakManager.postponeBreak(seconds: 300)
                default:
                    break
                }
            }
        }
    }

    // MARK: - Onboarding (#11)

    private func showOnboarding() {
        let onboardingView = OnboardingView(onComplete: { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        })
        .environmentObject(settings)

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Glance"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
