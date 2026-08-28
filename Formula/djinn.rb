class Djinn < Formula
  desc "Local-first companion for OpenCode and other AI coding agents"
  homepage "https://github.com/Noswad123/djinn"
  url "https://github.com/Noswad123/djinn.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  depends_on "bun" => :build
  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args(path: "crates/djinn-cli")
    system "make", "install-ui", "INSTALL_DIR=#{bin}"
  end

  test do
    assert_match "Local-first companion", shell_output("#{bin}/djinn --help")
    system "#{bin}/djinn-ui", "--version"
  end
end
