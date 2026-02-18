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
    private var reminderWindow: ReminderWindowController?
    private var onboardingWindow: NSWindow?
    private var idleReturnWindow: NSWindow?
    private let breakManager = BreakManager.shared
    private let wellness = WellnessManager.shared
    private let settings = AppSettings.shared
    private var eventMonitor: Any?
    private var clickMonitor: Any?
    private var escapeMonitor: Any?
    private var lastEscapeTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupNotificationObservers()
        wellness.start()
        setupGlobalShortcuts()

        // Onboarding (#11)
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "glance")
            button.image?.size = NSSize(width: 16, height: 16)
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
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
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarTitle()
            }
        }
    }

    @MainActor
    private func updateMenuBarTitle() {
        let style = settings.menuBarStyle

        // Icon visibility (#8, #15)
        if style == .textOnly || !settings.showMenuBarIcon {
            statusItem.button?.image = nil
        } else {
            if statusItem.button?.image == nil {
                let img = NSImage(systemSymbolName: "eye", accessibilityDescription: "glance")
                img?.size = NSSize(width: 16, height: 16)
                statusItem.button?.image = img
                statusItem.button?.imagePosition = .imageLeading
            }
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
        case .countdown(let s):
            statusItem.button?.title = " \(s)..."
        }
    }

    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                closePopover()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowBreakOverlay(_:)), name: .showBreakOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissBreakOverlay), name: .dismissBreakOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowBreakReminder), name: .showBreakReminder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissBreakReminder), name: .dismissBreakReminder, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowIdleReturnPrompt), name: .showIdleReturnPrompt, object: nil)
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

    // MARK: - Idle Return Prompt (#10)

    @objc private func handleShowIdleReturnPrompt() {
        DispatchQueue.main.async { [weak self] in
            self?.showIdleReturnAlert()
        }
    }

    private func showIdleReturnAlert() {
        guard idleReturnWindow == nil else { return }

        let alert = NSAlert()
        alert.messageText = "Did you take a break while away?"
        alert.informativeText = "You were away from your computer long enough for a break."
        alert.addButton(withTitle: "Yes, I rested")
        alert.addButton(withTitle: "No, I didn't")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // "No" — don't count as break, timer already reset
            // Could track this, but timer is already reset in checkIdle
        }
        // "Yes" — timer already reset normally
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
