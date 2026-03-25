import Foundation
import AppKit

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case error
}

@MainActor
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var checkState: UpdateCheckState = .idle
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseURL: URL?

    private let currentVersion: String
    private let repoOwner = "adikondepudi"
    private let repoName = "glance"
    private var checkTimer: Timer?

    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        // Check on launch after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates(silent: true)
        }
        // Check every 6 hours
        checkTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates(silent: true)
            }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        checkState = .checking

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            checkState = .error
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }

                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if !silent { self.checkState = .error }
                    else { self.checkState = .idle }
                    return
                }

                let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                let htmlURL = json["html_url"] as? String ?? ""

                if self.isNewer(latest, than: self.currentVersion) {
                    self.latestVersion = latest
                    self.releaseURL = URL(string: htmlURL)
                    self.updateAvailable = true
                    self.checkState = .available(version: latest)
                } else {
                    self.checkState = .upToDate
                    // Auto-clear "up to date" message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.checkState == .upToDate {
                            self.checkState = .idle
                        }
                    }
                }
            }
        }.resume()
    }

    func openReleasePage() {
        guard let url = releaseURL else { return }
        NSWorkspace.shared.open(url)
    }

    func dismissUpdate() {
        updateAvailable = false
        checkState = .idle
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
