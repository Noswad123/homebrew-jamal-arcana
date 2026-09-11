class Waystone < Formula
  desc "Save, fuzzy-pick, copy, and open frequently used paths"
  homepage "https://github.com/Noswad123/waystone"
  url "https://github.com/Noswad123/waystone.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  depends_on "rust" => :build
  depends_on "fzf"

  def install
    if File.exist?("Cargo.toml")
      system "cargo", "install", *std_cargo_args
    else
      bin.install "bin/waystone"
    end

    zsh_completion.install "completions/zsh/_waystone"
    bash_completion.install "completions/bash/waystone"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/waystone --help")
  end
end
