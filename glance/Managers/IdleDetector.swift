import Foundation
import IOKit

class IdleDetector {
    static let shared = IdleDetector()

    /// Testing hook: when non-nil, `systemIdleTime` returns this value instead
    /// of querying IOKit — lets tests simulate the user being away from the
    /// keyboard for a whole break (or typing right up to the end of one)
    /// without depending on real, unpredictable hardware idle time. `nil`
    /// (default) uses the normal IOKit-backed reading. Only ever set by test
    /// code.
    static var idleTimeOverrideForTesting: TimeInterval?

    /// Returns the number of seconds since the last user input event
    var systemIdleTime: TimeInterval {
        if let override = Self.idleTimeOverrideForTesting {
            return override
        }

        var iterator: io_iterator_t = 0
        defer { IOObjectRelease(iterator) }

        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return 0
        }

        let entry: io_registry_entry_t = IOIteratorNext(iterator)
        defer { IOObjectRelease(entry) }
        guard entry != 0 else { return 0 }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanagedDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
              let idleTime = dict["HIDIdleTime"] as? Int64 else {
            return 0
        }

        // HIDIdleTime is in nanoseconds
        return TimeInterval(idleTime) / 1_000_000_000
    }
}
