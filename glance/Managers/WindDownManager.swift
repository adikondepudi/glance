import Foundation
import AppKit
import Combine

@MainActor
class WindDownManager: ObservableObject {
    static let shared = WindDownManager()

    @Published var dismissCount: Int = 0

    private let settings = AppSettings.shared
    private var windDownTimer: Timer?
    private var isActive = false
    private var settingsObserver: AnyCancellable?
    private var lastWindDownEnabled = false
    private var lastWindDownInterval = 0

    private init() {
        lastWindDownEnabled = settings.windDownEnabled
        lastWindDownInterval = settings.windDownIntervalMinutes
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: .enteredOutsideSchedule,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleOutsideSchedule()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .enteredWorkingState,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }

        observeSettingsChanges()
    }

    private func observeSettingsChanges() {
        settingsObserver = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleSettingsChanged()
                }
            }
    }

    private func handleSettingsChanged() {
        let newEnabled = settings.windDownEnabled
        let newInterval = settings.windDownIntervalMinutes

        let enabledChanged = newEnabled != lastWindDownEnabled
        let intervalChanged = newInterval != lastWindDownInterval

        lastWindDownEnabled = newEnabled
        lastWindDownInterval = newInterval

        if enabledChanged {
            if newEnabled && BreakManager.shared.state == .outsideSchedule {
                dismissCount = 0
                startWindDownCycle()
            } else if !newEnabled {
                stop()
            }
        } else if intervalChanged && isActive {
            // Restart cycle with new interval
            startWindDownCycle()
        }
    }

    private func handleOutsideSchedule() {
        guard settings.windDownEnabled else { return }
        guard settings.officeHours.enabled else { return }

        dismissCount = 0
        startWindDownCycle()
    }

    private func startWindDownCycle() {
        windDownTimer?.invalidate()
        isActive = true

        let interval = TimeInterval(settings.windDownIntervalMinutes * 60)
        windDownTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.showWindDown()
            }
        }

        // Show first one after a short delay
        Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showWindDown()
            }
        }
    }

    private func showWindDown() {
        guard isActive else { return }
        // Don't show during active breaks
        if case .onBreak = BreakManager.shared.state { return }

        NotificationCenter.default.post(name: .showWindDownOverlay, object: nil)
    }

    func dismiss() {
        dismissCount += 1
        NotificationCenter.default.post(name: .dismissWindDownOverlay, object: nil)
    }

    func stop() {
        windDownTimer?.invalidate()
        isActive = false
        dismissCount = 0
        NotificationCenter.default.post(name: .dismissWindDownOverlay, object: nil)
    }

    var currentMessage: String {
        if let custom = settings.windDownMessage, !custom.isEmpty {
            return custom
        }

        if settings.windDownEscalation && dismissCount >= 3 {
            return "You've been working late for a while now. Please consider stopping for the night."
        } else if settings.windDownEscalation && dismissCount >= 1 {
            return "It's getting late. Think about wrapping up soon."
        }

        return "It's past your work hours. Time to wind down."
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showWindDownOverlay = Notification.Name("showWindDownOverlay")
    static let dismissWindDownOverlay = Notification.Name("dismissWindDownOverlay")
    static let enteredOutsideSchedule = Notification.Name("enteredOutsideSchedule")
    static let enteredWorkingState = Notification.Name("enteredWorkingState")
}
