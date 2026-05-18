class Wisp < Formula
  desc "Open commands in floating kitty terminal windows"
  homepage "https://github.com/Noswad123/wisp"
  url "https://github.com/Noswad123/wisp/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "945f17ad2cbbc12f1b2d512a3ce34bc4ce79cd57b7e9835ff5b2754cbd9d811c"
  license "MIT"

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
