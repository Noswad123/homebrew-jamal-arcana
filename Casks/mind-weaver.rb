cask "mind-weaver" do
  version "0.1.0"
  sha256 "62a3e11e68ba41839702d59d7ce97634508201b07ef64fe64919c5f2999b0b55"

  url "https://github.com/Noswad123/mind-weaver-swift/releases/download/v#{version}/MindWeaver-#{version}.zip",
      verified: "github.com/Noswad123/mind-weaver-swift/"
  name "MindWeaver"
  desc "Native shell for MindWeaver notes, todos, dashboards, and graphs"
  homepage "https://github.com/Noswad123/mind-weaver-swift"

  depends_on formula: "mw"
  depends_on macos: :ventura

  app "MindWeaver.app"

  caveats <<~EOS
    MindWeaver preview releases are not Developer ID notarized.
    If macOS blocks first launch, run:

      xattr -dr com.apple.quarantine /Applications/MindWeaver.app

    Then open MindWeaver again.
  EOS

  zap trash: [
    "~/Library/Application Support/MindWeaver",
    "~/Library/Caches/jamal-arcana.MindWeaver",
    "~/Library/Preferences/jamal-arcana.MindWeaver.plist",
    "~/Library/Saved Application State/jamal-arcana.MindWeaver.savedState",
  ]
end
