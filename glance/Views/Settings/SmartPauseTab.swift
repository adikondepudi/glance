import SwiftUI
import UniformTypeIdentifiers
import CoreAudio

struct SmartPauseTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingAppPicker = false
    @State private var availableMics: [(id: String, name: String)] = []

    var body: some View {
        Form {
            Section("Automatic Pause") {
                Toggle("Meetings or Calls", isOn: $settings.detectMeetings)
                    .help("Pauses breaks when camera or microphone is in use during a meeting app")

                if settings.detectMeetings && !availableMics.isEmpty {
                    Section("Microphone Devices") {
                        Text("Uncheck devices you want to ignore for meeting detection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(availableMics, id: \.id) { mic in
                            Toggle(mic.name, isOn: Binding(
                                get: { !settings.excludedMicDevices.contains(mic.id) },
                                set: { included in
                                    var excluded = settings.excludedMicDevices
                                    if included {
                                        excluded.removeAll { $0 == mic.id }
                                    } else {
                                        excluded.append(mic.id)
                                    }
                                    settings.excludedMicDevices = excluded
                                }
                            ))
                        }
                    }
                }

                Toggle("Video Playback", isOn: $settings.detectVideoPlayback)

                if settings.detectVideoPlayback {
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
        .onAppear { loadMicDevices() }
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

    private func loadMicDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return }

        var mics: [(id: String, name: String)] = []

        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr else { continue }
            guard inputSize > 0 else { continue }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPtr) == noErr else { continue }

            let bufferList = bufferListPtr.pointee
            guard bufferList.mNumberBuffers > 0, bufferList.mBuffers.mNumberChannels > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name) == noErr else { continue }

            mics.append((id: String(deviceID), name: name as String))
        }

        availableMics = mics
    }
}

extension SmartPauseTab {
    func onAppearLoad() -> some View {
        self.onAppear { loadMicDevices() }
    }
}
