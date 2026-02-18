import Foundation
import AppKit
import AVFoundation

class SoundManager {
    static let shared = SoundManager()

    private var player: AVAudioPlayer?
    private let settings = AppSettings.shared

    static let builtInSounds: [(name: String, id: String)] = [
        ("Chime", "chime"),
        ("Bell", "bell"),
        ("Gentle Ping", "ping"),
        ("Glass", "glass"),
        ("Breeze", "breeze"),
    ]

    private static let systemSoundMap: [String: String] = [
        "chime": "/System/Library/Sounds/Tink.aiff",
        "bell": "/System/Library/Sounds/Ping.aiff",
        "ping": "/System/Library/Sounds/Pop.aiff",
        "glass": "/System/Library/Sounds/Glass.aiff",
        "breeze": "/System/Library/Sounds/Breeze.aiff",
    ]

    func playBreakSound() {
        playSound(named: settings.selectedSound)
    }

    func playSound(named soundName: String) {
        let volume = Float(settings.soundVolume)

        var soundURL: URL?

        if let systemPath = Self.systemSoundMap[soundName] {
            soundURL = URL(fileURLWithPath: systemPath)
        } else if soundName.hasPrefix("/") || soundName.hasPrefix("~") {
            let expanded = NSString(string: soundName).expandingTildeInPath
            soundURL = URL(fileURLWithPath: expanded)
        }

        guard let url = soundURL, FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = volume
            player?.play()
        } catch {
            NSSound.beep()
        }
    }
}
