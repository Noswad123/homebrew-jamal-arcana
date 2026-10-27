class Yggdrasil < Formula
  desc "Share private files across Git worktrees with local history"
  homepage "https://github.com/Noswad123/yggdrasil"
  url "https://github.com/Noswad123/yggdrasil.git", branch: "main"
  version "0.1.0-dev"

  depends_on "go" => :build
  depends_on "git"

  def install
    system "go", "build", *std_go_args(output: bin/"ygg"), "./cmd/ygg"
  end

  test do
    output = shell_output("#{bin}/ygg help")
    assert_match "shared private files with local history", output
    assert_match "Hook installation is opt-in", output
    assert_match "install [--dry-run]", shell_output("#{bin}/ygg hooks help")
  end
end
