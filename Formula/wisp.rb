class Wisp < Formula
  desc "Command palette and floating utility surface launcher"
  homepage "https://github.com/Noswad123/wisp"
  url "https://github.com/Noswad123/wisp.git", branch: "main"
  version "0.2.0-dev"
  license "MIT"

  depends_on "go" => :build
  depends_on "fzf"

  def install
    system "go", "build", "-o", bin/"wisp", "./cmd/wisp"
    zsh_completion.install "completions/zsh/_wisp"
    bash_completion.install "completions/bash/wisp"
  end

  def caveats
    <<~EOS
      wisp opens commands in floating utility surfaces and can run a small
      action palette from ~/.config/wisp/actions.toml.

      Recommended companion tools:
        brew install --cask kitty
        brew install neovim
        brew install --cask nikitabobko/tap/aerospace

      kitty is the terminal backend. fzf powers `wisp palette`. neovim is
      optional but commonly used as `wisp nvim <file>`. Aerospace is optional
      and only needed for Aerospace-managed floating window placement.
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/wisp --help")
    assert_match "wisp: doctor", shell_output("#{bin}/wisp doctor")
  end
end
