import Foundation
import os.log

/// Bridges glance's break state to Apple's Focus modes.
///
/// There is no public API to set Focus directly, so this uses the same route
/// Shortcuts automations use: the user creates two shortcuts (default names
/// "Glance Break Started" / "Glance Break Ended") containing a "Set Focus"
/// action, and glance runs them via the `shortcuts` CLI when a break starts
/// and ends. Because Focus state syncs across a signed-in-user's devices via
/// iCloud, every Apple device picks up the same signal.
///
/// glance only sends the signal — what each device *does* with that Focus
/// (silence notifications, swap a lock screen, trigger a Personal Automation)
/// is entirely up to the user's own Shortcuts/Focus configuration. glance
/// never blocks anything on this: a missing shortcut, a `shortcuts` CLI
/// failure, or a timeout are all logged and otherwise ignored.
final class FocusBridgeManager {
    static let shared = FocusBridgeManager()

    private let settings = AppSettings.shared
    private let logger = Logger(subsystem: "com.glance.app", category: "FocusBridge")
    private static let shortcutsBinary = "/usr/bin/shortcuts"
    private static let commandTimeout: TimeInterval = 15

    private init() {}

    // MARK: - Break Hooks
    //
    // Called from the same points in BreakManager where AutomationManager's
    // break-start/break-end triggers fire.

    func breakDidStart() {
        guard settings.focusSyncEnabled else { return }
        run(shortcutNamed: settings.focusSyncStartShortcut)
    }

    func breakDidEnd() {
        guard settings.focusSyncEnabled else { return }
        run(shortcutNamed: settings.focusSyncEndShortcut)
    }

    // MARK: - Manual Test

    /// Runs the start shortcut, then the end shortcut a few seconds later, so
    /// the user can confirm the Focus actually toggles from the Settings UI.
    func runTest(startName: String, endName: String) {
        run(shortcutNamed: startName)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.run(shortcutNamed: endName)
        }
    }

    // MARK: - Running `shortcuts run`

    private func run(shortcutNamed name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.warning("Focus sync is enabled but no shortcut name is configured")
            return
        }

        // Always off the main thread and never awaited by the break flow —
        // a hung or missing shortcut must never delay the overlay.
        DispatchQueue.global(qos: .userInitiated).async { [logger] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.shortcutsBinary)
            process.arguments = ["run", trimmed]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                logger.error("Failed to launch shortcuts run \"\(trimmed, privacy: .public)\": \(error.localizedDescription, privacy: .public)")
                return
            }

            let deadline = DispatchTime.now() + Self.commandTimeout
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                }
            }
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                logger.warning("shortcuts run \"\(trimmed, privacy: .public)\" exited with status \(process.terminationStatus)")
            }
        }
    }

    // MARK: - Shortcut Existence Check (for Settings UI)

    /// Runs `shortcuts list` and reports, per requested name, whether it
    /// appears in the user's Shortcuts library. Calls back on the main thread.
    /// Never throws and never blocks the caller — this is UI status only, so
    /// any failure to run `shortcuts list` itself is reported as "not found"
    /// for every name.
    func checkExistence(of names: [String], completion: @escaping ([String: Bool]) -> Void) {
        DispatchQueue.global(qos: .utility).async { [logger] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.shortcutsBinary)
            process.arguments = ["list"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            let deadline = DispatchTime.now() + Self.commandTimeout
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                }
            }

            var existing: Set<String> = []
            do {
                try process.run()
                // Read before waiting to avoid deadlocking on a full pipe buffer.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                existing = Set(output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
            } catch {
                logger.error("Failed to run shortcuts list: \(error.localizedDescription, privacy: .public)")
            }

            // Not uniqueKeysWithValues: both fields can hold the same name.
            var result: [String: Bool] = [:]
            for name in names {
                result[name] = existing.contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
