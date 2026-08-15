cask "glance" do
  version "1.0.3"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # replace with `shasum -a 256` output for the release DMG — see packaging/homebrew/README.md

  url "https://github.com/adikondepudi/glance/releases/download/v#{version}/Glance-#{version}.dmg",
      verified: "github.com/adikondepudi/glance/"
  name "Glance"
  desc "Lightweight menu bar break reminder"
  homepage "https://github.com/adikondepudi/glance"

  # Once GitHub releases follow "vX.Y.Z" tags with a "Glance-X.Y.Z.dmg" asset,
  # this lets `brew livecheck` and `brew bump-cask-pr` find new versions automatically.
  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: ">= :sonoma"

  app "glance.app", target: "Glance.app"

  zap trash: [
    "~/Library/Preferences/com.glance.app.plist",
    "~/Library/Saved Application State/com.glance.app.savedState",
    "~/Library/HTTPStorages/com.glance.app",
  ]
end
