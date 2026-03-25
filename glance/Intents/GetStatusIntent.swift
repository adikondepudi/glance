import AppIntents

struct GlanceStatusEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Glance Status"
    static var defaultQuery = GlanceStatusQuery()

    var id: String
    var stateName: String
    var timeUntilBreak: String
    var breakTimeRemaining: String
    var breaksTaken: Int
    var isPaused: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(stateName)", subtitle: "Next break in \(timeUntilBreak)")
    }
}

struct GlanceStatusQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [GlanceStatusEntity] {
        let status = await fetchStatus()
        if identifiers.contains(status.id) {
            return [status]
        }
        return []
    }

    func suggestedEntities() async throws -> [GlanceStatusEntity] {
        [await fetchStatus()]
    }

    private func fetchStatus() async -> GlanceStatusEntity {
        await MainActor.run {
            let manager = BreakManager.shared
            let stateName: String
            switch manager.state {
            case .working:
                stateName = "Working"
            case .reminding:
                stateName = "Break reminder"
            case .onBreak(let isLong):
                stateName = isLong ? "Long break" : "Short break"
            case .paused:
                stateName = "Paused"
            case .smartPaused(let reason):
                stateName = "Smart paused (\(reason))"
            case .idle:
                stateName = "Idle"
            case .outsideSchedule:
                stateName = "Outside schedule"
            }

            return GlanceStatusEntity(
                id: "current",
                stateName: stateName,
                timeUntilBreak: manager.formattedTimeUntilBreak,
                breakTimeRemaining: manager.formattedBreakTimeRemaining,
                breaksTaken: manager.shortBreakCount,
                isPaused: manager.isPausedByUser
            )
        }
    }
}

struct GetStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Glance Status"
    static var description = IntentDescription("Check the current status of Glance, including time until next break.")

    func perform() async throws -> some IntentResult & ReturnsValue<GlanceStatusEntity> & ProvidesDialog {
        let status = try await GlanceStatusQuery().suggestedEntities().first
            ?? GlanceStatusEntity(id: "current", stateName: "Unknown", timeUntilBreak: "--:--", breakTimeRemaining: "--:--", breaksTaken: 0, isPaused: false)

        let dialog: IntentDialog
        switch status.stateName {
        case "Working":
            dialog = "Glance is in working mode. Next break in \(status.timeUntilBreak). You've taken \(status.breaksTaken) breaks so far."
        case "Paused":
            dialog = "Glance is paused. You've taken \(status.breaksTaken) breaks so far."
        case let name where name.contains("break"):
            dialog = "You're on a \(status.stateName.lowercased()). Time remaining: \(status.breakTimeRemaining)."
        default:
            dialog = "Glance status: \(status.stateName)."
        }

        return .result(value: status, dialog: dialog)
    }
}
