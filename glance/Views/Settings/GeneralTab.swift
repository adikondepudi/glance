import SwiftUI
import ServiceManagement
import os.log

struct GeneralTab: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var showResetConfirmation = false
    @State private var startShortcutExists: Bool?
    @State private var endShortcutExists: Bool?
    @State private var isTestingFocusSync = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Menu Bar") {
                Toggle("Show countdown timer in menu bar", isOn: $settings.showMenuBarTimer)

                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)

                if settings.showMenuBarIcon {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.callout)
                        HStack(spacing: 8) {
                            ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                                Button {
                                    settings.menuBarIcon = icon
                                } label: {
                                    Image(systemName: icon.rawValue)
                                        .font(.title3)
                                        .frame(width: 32, height: 32)
                                        .background(settings.menuBarIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Picker("Menu bar display", selection: Binding(
                    get: { settings.menuBarStyle },
                    set: { settings.menuBarStyle = $0 }
                )) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }

                if !settings.showMenuBarIcon && settings.menuBarStyle == .textOnly {
                    Text("Use keyboard shortcuts to control Glance if the icon is hidden.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Right-click the menu bar icon for quick actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Idle Detection") {
                Toggle("Reset timer when I'm away from the computer", isOn: $settings.idleDetectionEnabled)

                if settings.idleDetectionEnabled {
                    Picker("Consider idle after", selection: $settings.idleThresholdSeconds) {
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                    }

                    Text("Also triggers on screen lock, lid close, and system sleep.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Start break now") {
                    Text("⌘⇧B")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Start long break") {
                    Text("⌘⇧L")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Pause / Resume") {
                    Text("⌘⇧P")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Postpone 1 min") {
                    Text("⌘⇧1")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Postpone 5 min") {
                    Text("⌘⇧5")
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Focus Sync") {
                Toggle("Sync breaks to a Focus", isOn: $settings.focusSyncEnabled)
                    .onChange(of: settings.focusSyncEnabled) { _, newValue in
                        if newValue { refreshShortcutStatus() }
                    }

                if settings.focusSyncEnabled {
                    LabeledContent("Break start shortcut") {
                        TextField("Shortcut name", text: $settings.focusSyncStartShortcut)
                            .onSubmit { refreshShortcutStatus() }
                    }
                    shortcutStatusRow(name: settings.focusSyncStartShortcut, exists: startShortcutExists)

                    LabeledContent("Break end shortcut") {
                        TextField("Shortcut name", text: $settings.focusSyncEndShortcut)
                            .onSubmit { refreshShortcutStatus() }
                    }
                    shortcutStatusRow(name: settings.focusSyncEndShortcut, exists: endShortcutExists)

                    HStack {
                        Button("Test") {
                            testFocusSync()
                        }
                        .disabled(isTestingFocusSync)

                        if isTestingFocusSync {
                            ProgressView()
                                .controlSize(.small)
                            Text("Running start, then end in 5s…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Refresh Status") {
                            refreshShortcutStatus()
                        }
                    }

                    Text("Create two shortcuts in the Shortcuts app, each with a \"Set Focus\" action — one turns a Focus on, the other turns it off — named to match above. Glance runs them via the shortcuts CLI when a break starts and ends; it never sets Focus directly, so what each device does with the signal (via Focus sync or a Personal Automation) is up to you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                HStack {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    updateStatusView
                }
            }

            Section("Data") {
                Button("Reset All Settings…", role: .destructive) {
                    showResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if settings.focusSyncEnabled { refreshShortcutStatus() }
        }
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This will restore all settings to their defaults. This cannot be undone.")
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateManager.checkState {
        case .idle:
            Button("Check for Updates") {
                updateManager.checkForUpdates()
            }
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Up to date")
                    .foregroundStyle(.secondary)
            }
        case .available(let version):
            HStack(spacing: 6) {
                Text("v\(version) available")
                    .foregroundStyle(.orange)
                Button("Download") {
                    updateManager.openReleasePage()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case .error:
            HStack(spacing: 6) {
                Text("Check failed")
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    updateManager.checkForUpdates()
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutStatusRow(name: String, exists: Bool?) -> some View {
        HStack(spacing: 4) {
            switch exists {
            case .some(true):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\"\(name)\" found in Shortcuts")
                    .foregroundStyle(.secondary)
            case .some(false):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\"\(name)\" not found — create it in the Shortcuts app")
                    .foregroundStyle(.secondary)
            case .none:
                ProgressView()
                    .controlSize(.small)
                Text("Checking…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func refreshShortcutStatus() {
        startShortcutExists = nil
        endShortcutExists = nil
        let start = settings.focusSyncStartShortcut
        let end = settings.focusSyncEndShortcut
        FocusBridgeManager.shared.checkExistence(of: [start, end]) { result in
            startShortcutExists = result[start] ?? false
            endShortcutExists = result[end] ?? false
        }
    }

    private func testFocusSync() {
        isTestingFocusSync = true
        FocusBridgeManager.shared.runTest(startName: settings.focusSyncStartShortcut, endName: settings.focusSyncEndShortcut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            isTestingFocusSync = false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger(subsystem: "com.glance.app", category: "Settings").error("Failed to set launch at login: \(error.localizedDescription)")
            }
        }
    }

    private func resetAllSettings() {
        let domain = Bundle.main.bundleIdentifier ?? "com.glance.app"
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
