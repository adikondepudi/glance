import Foundation

/// Snapshots and restores specific `UserDefaults` keys so hosted unit tests can
/// freely rewrite settings without permanently clobbering whatever the
/// developer has configured for real.
///
/// Hosted XCTest bundles (TEST_HOST-based) run *inside* the actual
/// com.glance.app process, so `AppSettings.shared` — and any other code that
/// touches `UserDefaults.standard` — reads and writes the exact same defaults
/// domain as the developer's installed app. Every key a test might set must be
/// tracked here before it's touched, and restored afterward.
final class UserDefaultsSandbox {
    private let defaults: UserDefaults
    private var originalValues: [String: Any] = [:]
    private var originallyAbsent: Set<String> = []
    private var tracked: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records the current value (or absence) of each key the first time it's
    /// seen. Safe to call repeatedly, and with overlapping key lists.
    func track(_ keys: [String]) {
        for key in keys where !tracked.contains(key) {
            tracked.insert(key)
            if let value = defaults.object(forKey: key) {
                originalValues[key] = value
            } else {
                originallyAbsent.insert(key)
            }
        }
    }

    /// Restores every tracked key to exactly what it was before `track` first
    /// saw it, then forgets them.
    func restoreAll() {
        for key in tracked {
            if originallyAbsent.contains(key) {
                defaults.removeObject(forKey: key)
            } else if let value = originalValues[key] {
                defaults.set(value, forKey: key)
            }
        }
        tracked.removeAll()
        originalValues.removeAll()
        originallyAbsent.removeAll()
    }
}
