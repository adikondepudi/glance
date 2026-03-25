import Foundation

// MARK: - Stats Event

enum StatsEventType: String, Codable {
    case breakCompleted
    case breakStarted
    case breakSkipped
    case breakPostponed
    case focusCycleCompleted
    case screenTimeMinute
    case idleStarted
    case idleEnded
}

struct StatsEvent: Codable, Identifiable {
    let id: UUID
    let type: StatsEventType
    let timestamp: Date
    let isLongBreak: Bool?

    init(type: StatsEventType, isLongBreak: Bool? = nil) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.isLongBreak = isLongBreak
    }
}

// MARK: - Daily Stats

struct DailyStats: Codable {
    let date: String // yyyy-MM-dd
    var events: [StatsEvent]

    var breaksCompleted: Int {
        events.filter { $0.type == .breakCompleted }.count
    }

    var shortBreaksCompleted: Int {
        events.filter { $0.type == .breakCompleted && $0.isLongBreak != true }.count
    }

    var longBreaksCompleted: Int {
        events.filter { $0.type == .breakCompleted && $0.isLongBreak == true }.count
    }

    var breaksSkipped: Int {
        events.filter { $0.type == .breakSkipped }.count
    }

    var breaksPostponed: Int {
        events.filter { $0.type == .breakPostponed }.count
    }

    var focusCyclesCompleted: Int {
        events.filter { $0.type == .focusCycleCompleted }.count
    }

    var screenTimeMinutes: Int {
        events.filter { $0.type == .screenTimeMinute }.count
    }

    var completionRate: Double {
        let total = breaksCompleted + breaksSkipped
        guard total > 0 else { return 1.0 }
        return Double(breaksCompleted) / Double(total)
    }

    var screenScore: Int {
        let base = 20.0
        let completionBonus = completionRate * 80.0
        let postponePenalty = min(Double(breaksPostponed) * 2.0, 20.0)
        return max(0, min(100, Int(base + completionBonus - postponePenalty)))
    }
}

// MARK: - Period Stats (aggregated)

struct PeriodStats {
    let days: [DailyStats]

    var totalBreaksCompleted: Int { days.reduce(0) { $0 + $1.breaksCompleted } }
    var totalBreaksSkipped: Int { days.reduce(0) { $0 + $1.breaksSkipped } }
    var totalBreaksPostponed: Int { days.reduce(0) { $0 + $1.breaksPostponed } }
    var totalFocusCycles: Int { days.reduce(0) { $0 + $1.focusCyclesCompleted } }
    var totalScreenTimeMinutes: Int { days.reduce(0) { $0 + $1.screenTimeMinutes } }
    var totalShortBreaks: Int { days.reduce(0) { $0 + $1.shortBreaksCompleted } }
    var totalLongBreaks: Int { days.reduce(0) { $0 + $1.longBreaksCompleted } }

    var averageScreenScore: Int {
        guard !days.isEmpty else { return 0 }
        let total = days.reduce(0) { $0 + $1.screenScore }
        return total / days.count
    }

    var averageCompletionRate: Double {
        guard !days.isEmpty else { return 1.0 }
        let total = days.reduce(0.0) { $0 + $1.completionRate }
        return total / Double(days.count)
    }
}

// MARK: - Time Range

enum StatsTimeRange: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
}
