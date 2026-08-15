import Foundation
import Combine

@MainActor
class GardenManager: ObservableObject {
    static let shared = GardenManager()

    @Published var state: GardenState

    private let fileManager = FileManager.default
    private var saveTimer: Timer?
    private var needsSave = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var gardenFile: URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory.appendingPathComponent("com.glance.app/garden.json")
        }
        return appSupport.appendingPathComponent("com.glance.app/garden.json")
    }

    private init() {
        state = GardenState()
        load()
    }

    // MARK: - Computed Properties

    var stage: GardenStage {
        GardenStage(growth: state.growth)
    }

    var mood: CharacterMood {
        if state.growth <= 10 { return .sad }
        if state.growth >= 86 { return .happy }
        return .idle
    }

    // MARK: - Break Events

    func recordBreakCompleted(isLong: Bool) {
        let points: Int
        if state.postponedPending {
            points = isLong ? 8 : 4  // half reward if postponed first
            state.postponedPending = false
        } else {
            points = isLong ? 15 : 8
        }
        state.growth = min(100, state.growth + points)
        state.totalBreaksLifetime += 1
        state.highestGrowth = max(state.highestGrowth, state.growth)
        updateActiveDate()
        scheduleSave()
    }

    func recordBreakSkipped() {
        let penalty = state.postponedPending ? 15 : 12
        state.postponedPending = false
        state.growth = max(0, state.growth - penalty)
        // Deliberately not updateActiveDate(): skipping breaks shouldn't extend the streak
        scheduleSave()
    }

    func recordBreakPostponed() {
        state.postponedPending = true
        scheduleSave()
    }

    // MARK: - Daily Decay

    func checkDailyDecay() {
        let today = Self.dateString(for: Date())
        guard !state.lastActiveDate.isEmpty, state.lastActiveDate != today else {
            if state.lastActiveDate.isEmpty {
                state.lastActiveDate = today
                scheduleSave()
            }
            return
        }

        let calendar = Calendar.current
        let formatter = Self.dateFormatter
        guard let lastDate = formatter.date(from: state.lastActiveDate),
              let daysBetween = calendar.dateComponents([.day], from: lastDate, to: Date()).day,
              daysBetween > 1 else {
            return
        }

        // -2 per inactive day, capped at -14
        let inactiveDays = min(daysBetween - 1, 7)
        let decay = inactiveDays * 2
        state.growth = max(0, state.growth - decay)
        scheduleSave()
    }

    // MARK: - Persistence

    private func updateActiveDate() {
        let today = Self.dateString(for: Date())
        if state.lastActiveDate != today {
            // New day — check streak
            if !state.lastActiveDate.isEmpty {
                let calendar = Calendar.current
                if let lastDate = Self.dateFormatter.date(from: state.lastActiveDate),
                   let daysBetween = calendar.dateComponents([.day], from: lastDate, to: Date()).day,
                   daysBetween == 1 {
                    state.currentStreak += 1
                } else {
                    state.currentStreak = 1
                }
            } else {
                state.currentStreak = 1
            }
            state.lastActiveDate = today
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: gardenFile) else { return }
        if let saved = try? JSONDecoder().decode(GardenState.self, from: data) {
            state = saved
        }
    }

    private func ensureDirectory() {
        let dir = gardenFile.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
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
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: gardenFile, options: .atomic)
        }
    }

    func resetGarden() {
        state = GardenState()
        state.lastActiveDate = Self.dateString(for: Date())
        scheduleSave()
    }

    static func dateString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
