import Foundation

class AutomationManager {
    static let shared = AutomationManager()

    private let settings = AppSettings.shared

    func runAutomations(for trigger: AutomationAction.AutomationTrigger) {
        let automations = settings.automations.filter { $0.enabled && $0.trigger == trigger }

        for action in automations {
            if action.isAppleScript {
                runAppleScript(action.script)
            } else {
                runShellScript(action.script)
            }
        }
    }

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let script = NSAppleScript(source: source) else {
                print("[Automation] Failed to create AppleScript")
                return
            }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error = error {
                print("[Automation] AppleScript error: \(error)")
            }
        }
    }

    private func runShellScript(_ command: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = nil
            process.standardError = nil

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("[Automation] Shell script error: \(error)")
            }
        }
    }
}
