import AppIntents

struct PostponeBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Postpone Break"
    static var description = IntentDescription("Postpone the next break in Glance by a set amount of time.")

    @Parameter(title: "Duration")
    var duration: PostponeDuration

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await MainActor.run { BreakManager.shared.state }
        guard state == .working || state == .reminding else {
            throw GlanceIntentError.notWorking
        }
        let seconds = duration.rawValue
        await MainActor.run { BreakManager.shared.postponeBreak(seconds: seconds) }

        let label = PostponeDuration.caseDisplayRepresentations[duration]?.title ?? "a while"
        return .result(dialog: "Break postponed by \(label).")
    }
}

struct SkipBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Break"
    static var description = IntentDescription("Skip the current break or countdown in Glance.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await MainActor.run { BreakManager.shared.state }
        let canSkip = await MainActor.run { BreakManager.shared.canSkip }

        guard canSkip else {
            throw GlanceIntentError.cannotSkip
        }

        switch state {
        case .onBreak:
            await MainActor.run { BreakManager.shared.skipCurrentBreak() }
            return .result(dialog: "Break ended early.")
        default:
            throw GlanceIntentError.notInCountdown
        }
    }
}

struct ResetTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Reset Break Timer"
    static var description = IntentDescription("Reset the work timer in Glance, restarting the countdown to the next break.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { BreakManager.shared.resetWorkTimer() }
        return .result(dialog: "Break timer has been reset.")
    }
}
