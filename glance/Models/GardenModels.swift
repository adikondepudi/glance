import SwiftUI

// MARK: - State

struct GardenState: Codable {
    var growth: Int = 15
    var currentStreak: Int = 0
    var lastActiveDate: String = ""
    var totalBreaksLifetime: Int = 0
    var highestGrowth: Int = 15
    var postponedPending: Bool = false
}

// MARK: - Enums

enum GardenStage: String, CaseIterable, Codable {
    case empty
    case started
    case building
    case shaping
    case almostDone
    case complete

    init(growth: Int) {
        switch growth {
        case 0...15: self = .empty
        case 16...30: self = .started
        case 31...50: self = .building
        case 51...70: self = .shaping
        case 71...85: self = .almostDone
        default: self = .complete
        }
    }

    var displayName: String {
        switch self {
        case .empty: return "Empty"
        case .started: return "Just Started"
        case .building: return "Building Up"
        case .shaping: return "Taking Shape"
        case .almostDone: return "Almost Done"
        case .complete: return "Complete"
        }
    }
}

enum GardenThemeType: String, CaseIterable, Codable {
    case builder = "builder"
    case gardener = "gardener"

    var displayName: String {
        switch self {
        case .builder: return "Builder"
        case .gardener: return "Gardener"
        }
    }
}

enum CharacterMood {
    case idle
    case working
    case happy
    case sad
}

// MARK: - Pixel Grid

typealias PixelGrid = [[Color?]]

// MARK: - Theme Protocol

protocol GardenTheme {
    func pixelGrid(for stage: GardenStage, mood: CharacterMood) -> PixelGrid
}

func gardenTheme(for type: GardenThemeType) -> GardenTheme {
    switch type {
    case .builder: return BuilderTheme()
    case .gardener: return GardenerTheme()
    }
}
