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
    if OS.mac?
      system "swiftc", "-O", "-o", bin/"wisp-hint-macos", "cmd/wisp-hint-macos/main.swift"
    else
      bin.install "cmd/wisp-hint-linux/main.py" => "wisp-hint-linux"
      (bin/"wisp-hint-linux").chmod 0755
    end
    zsh_completion.install "completions/zsh/_wisp"
    bash_completion.install "completions/bash/wisp"
  end

  def caveats
    <<~EOS
      wisp palette [show|close|text] controls the native passive Palette.
      The window manager/compositor owns Option+Space (Alt+Space) bindings and
      prefix mode; showing Palette alone does not capture keys or enter mode.
      Palette and the explicit Kitty/fzf terminal interface, wisp menu, share
      the action catalog at ~/.config/wisp/actions.toml.

      Recommended companion tools:
        brew install --cask kitty
        brew install neovim
        brew install --cask nikitabobko/tap/aerospace

      Kitty and fzf are needed for the optional wisp menu, not native Palette.
      kitty is the terminal backend. neovim is
      optional but commonly used as `wisp nvim <file>`. Aerospace is optional
      and only needed for Aerospace-managed floating window placement.

      Installation does not modify the action catalog or window manager
      configuration, register autostart, or launch the native helper.
      #{if OS.linux?
          "\nThe Linux Wayland helper uses system /usr/bin/python3 and requires distro-provided\n" \
            "PyGObject, Pycairo, GTK 3 and gtk-layer-shell (not Homebrew Python packages)."
      end}
    EOS
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/wisp --help")
    assert_match "wisp: doctor", shell_output("#{bin}/wisp doctor")
    helper = OS.mac? ? "wisp-hint-macos" : "wisp-hint-linux"
    assert_predicate bin/helper, :executable?
  end
end
