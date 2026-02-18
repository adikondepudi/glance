import AppIntents

struct GlanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBreakIntent(),
            phrases: [
                "Take a break with \(.applicationName)",
                "Start a break in \(.applicationName)",
            ],
            shortTitle: "Start Break",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: StartLongBreakIntent(),
            phrases: [
                "Take a long break with \(.applicationName)",
            ],
            shortTitle: "Long Break",
            systemImageName: "eye.slash.fill"
        )
        AppShortcut(
            intent: PauseBreaksIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Pause breaks in \(.applicationName)",
            ],
            shortTitle: "Pause Breaks",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: ResumeBreaksIntent(),
            phrases: [
                "Resume \(.applicationName)",
                "Resume breaks in \(.applicationName)",
            ],
            shortTitle: "Resume Breaks",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: GetStatusIntent(),
            phrases: [
                "Check \(.applicationName) status",
                "How much time until my break in \(.applicationName)",
            ],
            shortTitle: "Check Status",
            systemImageName: "info.circle"
        )
    }
}
