import AppIntents

struct PauseBreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Breaks"
    static var description = IntentDescription("Pause all breaks in Glance until you resume.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let isPaused = await MainActor.run { BreakManager.shared.isPausedByUser }
        if isPaused {
            throw GlanceIntentError.alreadyPaused
        }
        await MainActor.run { BreakManager.shared.pauseByUser() }
        return .result(dialog: "Breaks are now paused.")
    }
}

struct ResumeBreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Breaks"
    static var description = IntentDescription("Resume breaks in Glance after pausing.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let isPaused = await MainActor.run { BreakManager.shared.isPausedByUser }
        if !isPaused {
            throw GlanceIntentError.notPaused
        }
        await MainActor.run { BreakManager.shared.resumeByUser() }
        return .result(dialog: "Breaks have been resumed.")
    }
}

struct PauseTemporarilyIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Breaks Temporarily"
    static var description = IntentDescription("Pause breaks in Glance for a set amount of time.")

    @Parameter(title: "Duration")
    var duration: PauseDuration

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let isPaused = await MainActor.run { BreakManager.shared.isPausedByUser }
        if isPaused {
            throw GlanceIntentError.alreadyPaused
        }
        let seconds = duration.rawValue
        await MainActor.run { BreakManager.shared.pauseTemporarily(seconds: seconds) }

        let label = PauseDuration.caseDisplayRepresentations[duration]?.title ?? "a while"
        return .result(dialog: "Breaks paused for \(label).")
    }
}
