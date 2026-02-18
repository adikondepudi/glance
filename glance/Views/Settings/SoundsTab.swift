import SwiftUI
import UniformTypeIdentifiers

struct SoundsTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            if settings.soundSettingsMigrated {
                perBreakTypeSounds
            } else {
                legacySounds
            }

            Section("Volume") {
                HStack {
                    Text("Volume")
                    Slider(value: $settings.soundVolume, in: 0...1)
                    Image(systemName: volumeIcon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }

                Button("Preview") {
                    SoundManager.shared.playBreakSound()
                }
            }

            Section {
                if !settings.soundSettingsMigrated {
                    Button("Enable per-break-type sounds") {
                        settings.playSoundShortBreakStart = settings.playSoundOnBreakStart
                        settings.playSoundShortBreakEnd = settings.playSoundOnBreakEnd
                        settings.playSoundLongBreakStart = settings.playSoundOnBreakStart
                        settings.playSoundLongBreakEnd = settings.playSoundOnBreakEnd
                        settings.selectedSoundShortBreakStart = settings.selectedSound
                        settings.selectedSoundShortBreakEnd = settings.selectedSound
                        settings.selectedSoundLongBreakStart = settings.selectedSound
                        settings.selectedSoundLongBreakEnd = settings.selectedSound
                        settings.soundSettingsMigrated = true
                    }

                    Text("Configure different sounds for short and long break start/end events.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Per-Break-Type Sounds

    @ViewBuilder
    private var perBreakTypeSounds: some View {
        Section("Short Break Start") {
            Toggle("Play sound", isOn: $settings.playSoundShortBreakStart)
            if settings.playSoundShortBreakStart {
                SoundPickerRow(selectedSound: $settings.selectedSoundShortBreakStart)
            }
        }

        Section("Short Break End") {
            Toggle("Play sound", isOn: $settings.playSoundShortBreakEnd)
            if settings.playSoundShortBreakEnd {
                SoundPickerRow(selectedSound: $settings.selectedSoundShortBreakEnd)
            }
        }

        Section("Long Break Start") {
            Toggle("Play sound", isOn: $settings.playSoundLongBreakStart)
            if settings.playSoundLongBreakStart {
                SoundPickerRow(selectedSound: $settings.selectedSoundLongBreakStart)
            }
        }

        Section("Long Break End") {
            Toggle("Play sound", isOn: $settings.playSoundLongBreakEnd)
            if settings.playSoundLongBreakEnd {
                SoundPickerRow(selectedSound: $settings.selectedSoundLongBreakEnd)
            }
        }
    }

    // MARK: - Legacy Sounds

    @ViewBuilder
    private var legacySounds: some View {
        Section("Break Sounds") {
            Toggle("Play sound when break starts", isOn: $settings.playSoundOnBreakStart)
            Toggle("Play sound when break ends", isOn: $settings.playSoundOnBreakEnd)
        }

        Section("Sound") {
            Picker("Sound", selection: $settings.selectedSound) {
                ForEach(SoundManager.builtInSounds, id: \.id) { sound in
                    Text(sound.name).tag(sound.id)
                }

                Divider()

                if settings.selectedSound.hasPrefix("/") || settings.selectedSound.hasPrefix("~") {
                    Text(URL(fileURLWithPath: settings.selectedSound).lastPathComponent)
                        .tag(settings.selectedSound)
                }

                Text("Custom Sound...").tag("__custom__")
            }
            .onChange(of: settings.selectedSound) { newValue in
                if newValue == "__custom__" {
                    pickCustomSound(binding: $settings.selectedSound)
                }
            }
        }
    }

    private var volumeIcon: String {
        if settings.soundVolume == 0 { return "speaker.slash" }
        if settings.soundVolume < 0.33 { return "speaker.wave.1" }
        if settings.soundVolume < 0.66 { return "speaker.wave.2" }
        return "speaker.wave.3"
    }

    private func pickCustomSound(binding: Binding<String>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            binding.wrappedValue = url.path
        } else {
            binding.wrappedValue = "chime"
        }
    }
}

// MARK: - Reusable Sound Picker Row

struct SoundPickerRow: View {
    @Binding var selectedSound: String

    var body: some View {
        Picker("Sound", selection: $selectedSound) {
            ForEach(SoundManager.builtInSounds, id: \.id) { sound in
                Text(sound.name).tag(sound.id)
            }

            Divider()

            if selectedSound.hasPrefix("/") || selectedSound.hasPrefix("~") {
                Text(URL(fileURLWithPath: selectedSound).lastPathComponent)
                    .tag(selectedSound)
            }

            Text("Custom Sound...").tag("__custom__")
        }
        .onChange(of: selectedSound) { newValue in
            if newValue == "__custom__" {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.audio]
                panel.allowsMultipleSelection = false

                if panel.runModal() == .OK, let url = panel.url {
                    selectedSound = url.path
                } else {
                    selectedSound = "chime"
                }
            }
        }

        Button("Preview") {
            SoundManager.shared.playSound(named: selectedSound)
        }
    }
}
