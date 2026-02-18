import Foundation
import AppKit

@MainActor
class WindDownManager: ObservableObject {
    static let shared = WindDownManager()

    @Published var dismissCount: Int = 0

    private let settings = AppSettings.shared
    private var windDownTimer: Timer?
    private var isActive = false

    private init() {}

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
