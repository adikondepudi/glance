import Foundation
import os.log

class AutomationManager {
    static let shared = AutomationManager()

    private let settings = AppSettings.shared
    private let logger = Logger(subsystem: "com.glance.app", category: "Automation")
    private static let maxScriptLength = 10_000
    private static let scriptTimeout: TimeInterval = 30

    func runAutomations(for trigger: AutomationAction.AutomationTrigger) {
        let automations = settings.automations.filter { $0.enabled && $0.trigger == trigger }

        for action in automations {
            guard action.script.count <= Self.maxScriptLength else { continue }

            if action.isAppleScript {
                runAppleScript(action.script)
            } else {
                runShellScript(action.script)
            }
        }
    }

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            guard let script = NSAppleScript(source: source) else {
                logger.error("Failed to create AppleScript")
                return
            }

            let semaphore = DispatchSemaphore(value: 0)
            var scriptError: NSDictionary?

            let thread = Thread {
                script.executeAndReturnError(&scriptError)
                semaphore.signal()
            }
            thread.start()

            let result = semaphore.wait(timeout: .now() + Self.scriptTimeout)
            if result == .timedOut {
                thread.cancel()
                logger.warning("AppleScript timed out after \(Self.scriptTimeout)s")
            } else if let error = scriptError {
                logger.error("AppleScript error: \(error)")
            }
        }
    }

    private func runShellScript(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                logger.error("Shell script failed to launch: \(error.localizedDescription)")
                return
            }

            let deadline = DispatchTime.now() + Self.scriptTimeout
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if process.isRunning {
                    process.terminate()
                }
            }
            process.waitUntilExit()
        }
    }
}
