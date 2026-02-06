import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Menu Bar") {
                Toggle("Show countdown timer in menu bar", isOn: $settings.showMenuBarTimer)
            }

            Section("Idle Detection") {
                Toggle("Pause timer when I'm away from the computer", isOn: $settings.idleDetectionEnabled)

                if settings.idleDetectionEnabled {
                    Picker("Consider idle after", selection: $settings.idleThresholdSeconds) {
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("3 minutes").tag(180)
                        Text("5 minutes").tag(300)
                    }
                }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Start break now") {
                    Text("⌘⇧B")
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("Pause / Resume") {
                    Text("⌘⇧P")
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Data") {
                Button("Reset All Settings…", role: .destructive) {
                    showResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This will restore all settings to their defaults. This cannot be undone.")
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
                print("Failed to set launch at login: \(error)")
            }
        }
    }

    private func resetAllSettings() {
        let domain = Bundle.main.bundleIdentifier ?? "com.glance.app"
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}
