import Foundation

struct CustomReminder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var message: String
    var intervalMinutes: Int
    var soundEnabled: Bool
    var enabled: Bool

    init(name: String = "", message: String = "", intervalMinutes: Int = 30, soundEnabled: Bool = true, enabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.message = message
        self.intervalMinutes = intervalMinutes
        self.soundEnabled = soundEnabled
        self.enabled = enabled
    }
}
