import SwiftUI
import UniformTypeIdentifiers

struct SoundsTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
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
                        pickCustomSound()
                    }
                }

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
        }
        .formStyle(.grouped)
    }

    private var volumeIcon: String {
        if settings.soundVolume == 0 { return "speaker.slash" }
        if settings.soundVolume < 0.33 { return "speaker.wave.1" }
        if settings.soundVolume < 0.66 { return "speaker.wave.2" }
        return "speaker.wave.3"
    }

    private func pickCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.selectedSound = url.path
        } else {
            // Revert to default if cancelled
            settings.selectedSound = "chime"
        }
    }
}
