class Waystone < Formula
  desc "Save, fuzzy-pick, copy, and open frequently used paths"
  homepage "https://github.com/Noswad123/waystone"
  url "https://github.com/Noswad123/waystone/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "a76276376875f506c86f88684f6d7e04c02a5a7d02f34eb6508cb11378443603"
  license "MIT"

  depends_on "fzf"

  def install
    bin.install "bin/waystone"
    zsh_completion.install "completions/zsh/_waystone"
    bash_completion.install "completions/bash/waystone"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/waystone --help")
  end
end
