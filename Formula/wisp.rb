class Wisp < Formula
  desc "Open commands in floating kitty terminal windows"
  homepage "https://github.com/Noswad123/wisp"
  url "https://github.com/Noswad123/wisp/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "4cee5f59246a661824179753e8c990ebca4b0c03d68d8dd46cab46bd2ce8d2d1"
  license "MIT"
  head "https://github.com/Noswad123/wisp.git", branch: "main"

  def install
    bin.install "bin/wisp"
    zsh_completion.install "completions/zsh/_wisp"
    bash_completion.install "completions/bash/wisp"
  end

  def caveats
    <<~EOS
      wisp opens commands in kitty floating windows on macOS.
      Make sure kitty is installed and available in /Applications or on PATH.
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/wisp --help")
  end
end
