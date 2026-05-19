class Mw < Formula
  desc "Local-first notes, todos, and optional Hive Mind sync CLI"
  homepage "https://github.com/Noswad123/mind-weaver"
  url "https://github.com/Noswad123/mind-weaver/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "029bfb1cc49707ebab12dc728a60b8a831e7c96bfdc09ad27df06329d0407db4"
  license "MIT"

  depends_on "go" => :build

  def install
    system "go", "build", *std_go_args(ldflags: "-s -w", output: bin/"mw"), "./cmd/mw"
  end

  test do
    assert_match "Synthesize notes", shell_output("#{bin}/mw --help")
  end
end
