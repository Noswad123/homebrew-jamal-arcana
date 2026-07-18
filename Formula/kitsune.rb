class Kitsune < Formula
  desc "Composable multiplexer kits for named working sessions"
  homepage "https://github.com/Noswad123/kitsune"
  url "https://github.com/Noswad123/kitsune.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match "Kitsune: composable multiplexer kits", shell_output("#{bin}/kit --help")
  end
end
