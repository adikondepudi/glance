import Foundation
import Combine

@MainActor
class StatsManager: ObservableObject {
    static let shared = StatsManager()

    @Published var todayStats: DailyStats

    private let fileManager = FileManager.default
    private var saveTimer: Timer?
    private var needsSave = false
    private var screenTimeTimer: Timer?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Testing hook: redirects on-disk persistence to a scratch location so
    /// unit tests (which run hosted inside the real com.glance.app bundle,
    /// sharing its Application Support directory) never read or write the
    /// developer's real stats history. `nil` (default) uses the normal path.
    static var statsDirectoryOverrideForTesting: URL?

    private var statsDirectory: URL {
        if let override = Self.statsDirectoryOverrideForTesting {
            return override
        }
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory.appendingPathComponent("com.glance.app/stats")
        }
        return appSupport.appendingPathComponent("com.glance.app/stats")
    }

    private init() {
        let today = Self.dateString(for: Date())
        todayStats = DailyStats(date: today, events: [])
        loadToday()
        startScreenTimeTracking()
    }

    // MARK: - Recording Events

    func recordBreakStarted(isLong: Bool) {
        let event = StatsEvent(type: .breakStarted, isLongBreak: isLong)
        todayStats.events.append(event)
        scheduleSave()
    }

    func recordBreakCompleted(isLong: Bool) {
        let event = StatsEvent(type: .breakCompleted, isLongBreak: isLong)
        todayStats.events.append(event)
        scheduleSave()
    }

    func recordBreakSkipped() {
        let event = StatsEvent(type: .breakSkipped)
        todayStats.events.append(event)
        scheduleSave()
    }

    func recordBreakPostponed() {
        let event = StatsEvent(type: .breakPostponed)
        todayStats.events.append(event)
        scheduleSave()
    }

    func recordIdleStarted() {
        let event = StatsEvent(type: .idleStarted)
        todayStats.events.append(event)
        scheduleSave()
    }

    func recordIdleEnded() {
        let event = StatsEvent(type: .idleEnded)
        todayStats.events.append(event)
        scheduleSave()
    }

    func recordFocusCycleCompleted() {
        let event = StatsEvent(type: .focusCycleCompleted)
        todayStats.events.append(event)
        scheduleSave()
    }

    /// Records the outcome of input-idle verification for a completed
    /// movement long break: `moved` is true when the user was away from the
    /// keyboard/mouse for essentially the whole break.
    func recordMovementBreak(moved: Bool) {
        let event = StatsEvent(type: .movementBreak, moved: moved)
        todayStats.events.append(event)
        scheduleSave()
    }

    // MARK: - Screen Time Tracking

    private func startScreenTimeTracking() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordScreenTimeMinute()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        screenTimeTimer = timer
    }

    private func recordScreenTimeMinute() {
        ensureTodayDate()
        // Only count minutes actively spent working — not idle, paused,
        // on break, or outside schedule (matches BreakManager.totalScreenTime)
        switch BreakManager.shared.state {
        case .working, .reminding:
            break
        default:
            return
        }
        let event = StatsEvent(type: .screenTimeMinute)
        todayStats.events.append(event)
        scheduleSave()
    }

    // MARK: - Querying

    func stats(for range: StatsTimeRange) -> PeriodStats {
        let calendar = Calendar.current
        let today = Date()
        let days: [DailyStats]

        switch range {
        case .today:
            days = [todayStats]
        case .week:
            guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today) else {
                days = [todayStats]
                break
            }
            days = loadDays(from: weekStart, to: today)
        case .month:
            guard let monthStart = calendar.date(byAdding: .day, value: -29, to: today) else {
                days = [todayStats]
                break
            }
            days = loadDays(from: monthStart, to: today)
        }

        return PeriodStats(days: days)
    }

    // MARK: - Persistence

    private func ensureDirectory() {
        try? fileManager.createDirectory(at: statsDirectory, withIntermediateDirectories: true)
    }

    private func filePath(for dateString: String) -> URL {
        statsDirectory.appendingPathComponent("\(dateString).json")
    }

    private func loadToday() {
        let today = Self.dateString(for: Date())
        if let saved = loadDay(today) {
            todayStats = saved
        }
    }

    private func ensureTodayDate() {
        let today = Self.dateString(for: Date())
        if todayStats.date != today {
            saveNow()
            todayStats = loadDay(today) ?? DailyStats(date: today, events: [])
        }
    }

    private func loadDay(_ dateString: String) -> DailyStats? {
        let path = filePath(for: dateString)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(DailyStats.self, from: data)
    }

    private func loadDays(from start: Date, to end: Date) -> [DailyStats] {
        var days: [DailyStats] = []
        let calendar = Calendar.current
        var current = start

        while current <= end {
            let dateStr = Self.dateString(for: current)
            if dateStr == todayStats.date {
                days.append(todayStats)
            } else if let day = loadDay(dateStr) {
                days.append(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return days
    }

    private func scheduleSave() {
        needsSave = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.saveNow()
            }
        }
    }

    func saveNow() {
        guard needsSave else { return }
        needsSave = false
        ensureDirectory()

        let path = filePath(for: todayStats.date)
        if let data = try? JSONEncoder().encode(todayStats) {
            try? data.write(to: path, options: .atomic)
        }
    }

    static func dateString(for date: Date) -> String {
        return dateFormatter.string(from: date)
    }
}
