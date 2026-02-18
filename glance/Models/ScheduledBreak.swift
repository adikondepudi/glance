import Foundation

struct ScheduledBreak: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var hour: Int
    var minute: Int
    var durationSeconds: Int
    var activeDays: Set<Int> // Calendar weekday: Sun=1, Mon=2, ...
    var enabled: Bool

    init(name: String = "", hour: Int = 12, minute: Int = 0, durationSeconds: Int = 300, activeDays: Set<Int> = [2, 3, 4, 5, 6], enabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.hour = hour
        self.minute = minute
        self.durationSeconds = durationSeconds
        self.activeDays = activeDays
        self.enabled = enabled
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let components = DateComponents(hour: hour, minute: minute)
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):\(String(format: "%02d", minute))"
    }
}
