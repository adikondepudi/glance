import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var breakManager: BreakManager
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var updateManager = UpdateManager.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            if updateManager.updateAvailable {
                updateBanner
                Divider()
            }
            timerSection
            Divider()
            actionsSection
            Divider()
            footerSection
        }
        .frame(width: 280)
    }

    private var updateBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Glance \(updateManager.latestVersion) available")
                    .font(.caption.weight(.medium))
            }
            Spacer()
            Button("Update") {
                updateManager.openReleasePage()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                updateManager.dismissUpdate()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var stateIcon: String {
        switch breakManager.state {
        case .working, .reminding: return "eye"
        case .onBreak: return "eye.slash"
        case .paused, .smartPaused: return "pause.circle"
        case .idle: return "moon"
        case .outsideSchedule: return "clock.badge.xmark"
        }
    }

    private var stateDescription: String {
        switch breakManager.state {
        case .working: return "Working"
        case .reminding: return "Break coming up"
        case .onBreak(let isLong): return isLong ? "Long break" : "Short break"
        case .paused: return "Paused"
        case .smartPaused(let reason): return "Paused — \(reason)"
        case .idle: return "Idle"
        case .outsideSchedule: return "Outside schedule"
        }
    }

    // MARK: - Timer

    private var timerSection: some View {
        VStack(spacing: 8) {
            switch breakManager.state {
            case .working, .reminding:
                Text(breakManager.formattedTimeUntilBreak)
                    .font(.system(size: 24, weight: .medium).monospacedDigit())

                Text(stateDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: workProgress)
                    .tint(.accentColor)

            case .onBreak:
                Text(breakManager.formattedBreakTimeRemaining)
                    .font(.system(size: 24, weight: .medium).monospacedDigit())
                    .foregroundColor(.accentColor)

                Text(stateDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: breakManager.breakProgress)
                    .tint(.accentColor)

            default:
                Image(systemName: stateIcon)
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(stateDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label("\(breakManager.shortBreakCount)", systemImage: "arrow.clockwise")
                    .help("Breaks taken")
                Label(formatDuration(breakManager.totalScreenTime), systemImage: "desktopcomputer")
                    .help("Screen time")
                Label("\(StatsManager.shared.todayStats.screenScore)", systemImage: "chart.bar")
                    .help("Screen Score")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            // Pomodoro cycle counter
            if settings.timerMode == .pomodoro {
                Text(breakManager.formattedPomodoroCycle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Time since last break (#1)
            if case .working = breakManager.state {
                Text(breakManager.formattedTimeSinceLastBreak)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding()
    }

    private var workProgress: Double {
        let total = Double(settings.shortBreakInterval * 60)
        let remaining = Double(breakManager.secondsUntilBreak)
        guard total > 0 else { return 0 }
        return 1.0 - (remaining / total)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 6) {
            if breakManager.state == .paused || breakManager.isPausedByUser {
                Button {
                    breakManager.resumeByUser()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    breakManager.startBreakNow()
                } label: {
                    Label("Take a Break", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                HStack(spacing: 6) {
                    Menu("Pause") {
                        Button("Pause for 5 min") { breakManager.pauseTemporarily(seconds: 300) }
                        Button("Pause for 15 min") { breakManager.pauseTemporarily(seconds: 900) }
                        Button("Pause for 30 min") { breakManager.pauseTemporarily(seconds: 1800) }
                        Button("Pause for 1 hour") { breakManager.pauseTemporarily(seconds: 3600) }
                        Divider()
                        Button("Pause indefinitely") { breakManager.pauseByUser() }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    if settings.longBreakEnabled && !isOnBreakOrCountdown {
                        Button("Long Break") {
                            breakManager.startLongBreakNow()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.regular)
            }
        }
        .padding()
    }

    private var isOnBreakOrCountdown: Bool {
        switch breakManager.state {
        case .onBreak: return true
        default: return false
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            settingsButton

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var settingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .dismissPopover, object: nil)
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Settings…", systemImage: "gear")
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

#Preview {
    MenuBarView()
        .environmentObject(BreakManager.shared)
        .environmentObject(AppSettings.shared)
}
