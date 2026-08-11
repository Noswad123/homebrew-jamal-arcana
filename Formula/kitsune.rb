class Kitsune < Formula
  desc "Composable multiplexer kits for named working sessions"
  homepage "https://github.com/Noswad123/kitsune"
  url "https://github.com/Noswad123/kitsune.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  depends_on "rust" => :build
  depends_on "zig@0.15" => :build

  def install
    ENV["ZIG"] = Formula["zig@0.15"].opt_bin/"zig"
    ENV["ZIG_GLOBAL_CACHE_DIR"] = buildpath/".zig-cache"
    ENV["ZIG_LOCAL_CACHE_DIR"] = buildpath/".zig-cache"

    system "cargo", "install", *std_cargo_args
  end

  test do
    assert_match "terminal workspace manager", shell_output("#{bin}/kitsune --help")
  end
end
