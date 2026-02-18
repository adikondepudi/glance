import AppIntents

struct StartBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Break"
    static var description = IntentDescription("Start a break immediately in Glance.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await MainActor.run { BreakManager.shared.state }
        if case .onBreak = state {
            throw GlanceIntentError.notWorking
        }
        if case .outsideSchedule = state {
            throw GlanceIntentError.outsideSchedule
        }
        await MainActor.run { BreakManager.shared.startBreakNow() }
        return .result(dialog: "Starting a break now.")
    }
}

struct StartLongBreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Long Break"
    static var description = IntentDescription("Start a long break immediately in Glance.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = await MainActor.run { BreakManager.shared.state }
        if case .onBreak = state {
            throw GlanceIntentError.notWorking
        }
        if case .outsideSchedule = state {
            throw GlanceIntentError.outsideSchedule
        }
        await MainActor.run { BreakManager.shared.startLongBreakNow() }
        return .result(dialog: "Starting a long break now.")
    }
}
