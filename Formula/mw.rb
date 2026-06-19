class Mw < Formula
  desc "Local-first notes, todos, and optional Hive Mind sync CLI"
  homepage "https://github.com/Noswad123/mind-weaver"
  url "https://github.com/Noswad123/mind-weaver/archive/refs/tags/v0.1.3.tar.gz"
  sha256 "e2ef2f13a3d0af06f61ef0f86f347817dba818f70121eea1abacbb3599c4e0a6"
  license "MIT"
  head "https://github.com/Noswad123/mind-weaver.git", branch: "main"

  depends_on "go" => :build

  def install
    ldflags = %W[
      -s -w
      -X github.com/Noswad123/mind-weaver/internal/version.Version=#{build.head? ? "HEAD" : version}
      -X github.com/Noswad123/mind-weaver/internal/version.Commit=#{build.head? ? "main" : "homebrew"}
      -X github.com/Noswad123/mind-weaver/internal/version.Date=homebrew
    ].join(" ")

    system "go", "build", *std_go_args(ldflags: ldflags, output: bin/"mw"), "./cmd/mw"
  end

  test do
    assert_match "Synthesize notes", shell_output("#{bin}/mw --help")
    assert_match build.head? ? "HEAD" : version.to_s, shell_output("#{bin}/mw version --short")
  end
end
