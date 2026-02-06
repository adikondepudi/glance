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
    private var floatingCountdown: FloatingCountdownController?
    private let breakManager = BreakManager.shared
    private let wellness = WellnessManager.shared
    private var eventMonitor: Any?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupNotificationObservers()
        wellness.start()
        setupGlobalShortcuts()
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
        guard AppSettings.shared.showMenuBarTimer else {
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowCountdown), name: .showBreakCountdown, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDismissCountdown), name: .dismissBreakCountdown, object: nil)
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

    @objc private func handleShowCountdown() {
        DispatchQueue.main.async { [weak self] in
            self?.showFloatingCountdown()
        }
    }

    @objc private func handleDismissCountdown() {
        DispatchQueue.main.async { [weak self] in
            self?.dismissFloatingCountdown()
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
    }

    private func dismissBreakOverlay() {
        for controller in breakWindowControllers {
            controller.close()
        }
        breakWindowControllers.removeAll()
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

    // MARK: - Floating Countdown

    private func showFloatingCountdown() {
        guard AppSettings.shared.showFloatingCountdown else { return }
        dismissFloatingCountdown()
        floatingCountdown = FloatingCountdownController()
        floatingCountdown?.showWindow(nil)
    }

    private func dismissFloatingCountdown() {
        floatingCountdown?.close()
        floatingCountdown = nil
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
                default:
                    break
                }
            }
        }
    }
}
