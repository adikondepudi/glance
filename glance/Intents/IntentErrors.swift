import Foundation
import AppIntents

enum GlanceIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notWorking
    case notOnBreak
    case notInCountdown
    case alreadyPaused
    case notPaused
    case cannotSkip
    case outsideSchedule

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notWorking:
            "Glance isn't in working mode right now."
        case .notOnBreak:
            "You're not currently on a break."
        case .notInCountdown:
            "There's no break countdown to skip."
        case .alreadyPaused:
            "Glance is already paused."
        case .notPaused:
            "Glance isn't paused."
        case .cannotSkip:
            "Skipping is disabled in your current settings."
        case .outsideSchedule:
            "Glance is outside your scheduled hours."
        }
    }
}
