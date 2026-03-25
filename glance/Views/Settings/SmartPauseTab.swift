import SwiftUI
import UniformTypeIdentifiers

struct SmartPauseTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Automatic Pause") {
                Toggle("Camera in Use", isOn: $settings.detectMeetings)
                    .help("Pauses breaks when your camera is active (meetings, video calls, recording)")

                Toggle("Video Playback", isOn: $settings.detectVideoPlayback)

                if settings.detectVideoPlayback {
                    Text("Detects native video apps and fullscreen browsers. For windowed browser video, add your browser as a Deep Focus app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Detection mode", selection: Binding(
                        get: { settings.videoPlaybackMode },
                        set: { settings.videoPlaybackMode = $0 }
                    )) {
                        ForEach(SmartPauseVideoMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                }

                Toggle("Screen Recording & Sharing", isOn: $settings.detectScreenRecording)
                Toggle("Screenshot Tools", isOn: $settings.detectScreenshots)
                    .help("Pauses breaks when screenshot tools like CleanShot X or Shottr are active")
                Toggle("Fullscreen Gaming", isOn: $settings.detectFullscreenGaming)
            }

            Section("Deep Focus Apps") {
                Text("Breaks are paused when these apps are active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(settings.deepFocusApps) { app in
                    HStack {
                        if let icon = appIcon(for: app.bundleIdentifier) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                        }

                        Text(app.name)

                        Spacer()

                        Picker("", selection: Binding(
                            get: { app.mode },
                            set: { newMode in
                                var apps = settings.deepFocusApps
                                if let idx = apps.firstIndex(where: { $0.id == app.id }) {
                                    apps[idx] = DeepFocusApp(name: app.name, bundleIdentifier: app.bundleIdentifier, mode: newMode)
                                    settings.deepFocusApps = apps
                                }
                            }
                        )) {
                            ForEach(DeepFocusMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .frame(width: 180)

                        Button(role: .destructive) {
                            settings.deepFocusApps.removeAll { $0.id == app.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add an App...") {
                    pickApp()
                }
            }

            Section("Cooldown") {
                HStack {
                    Text("Delay after activity ends")
                    Picker("", selection: $settings.smartPauseCooldown) {
                        Text("No delay").tag(0)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                Text("Prevents a break from starting immediately after an activity ends.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            let bundle = Bundle(url: url)
            let name = bundle?.infoDictionary?["CFBundleName"] as? String
                ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            let bundleID = bundle?.bundleIdentifier ?? url.lastPathComponent

            let app = DeepFocusApp(name: name, bundleIdentifier: bundleID, mode: .foreground)

            if !settings.deepFocusApps.contains(where: { $0.bundleIdentifier == bundleID }) {
                var apps = settings.deepFocusApps
                apps.append(app)
                settings.deepFocusApps = apps
            }
        }
    }

    private func appIcon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
