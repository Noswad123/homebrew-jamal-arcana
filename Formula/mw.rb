class Mw < Formula
  desc "Local-first notes, todos, and optional Hive Mind sync CLI"
  homepage "https://github.com/Noswad123/mind-weaver"
  url "https://github.com/Noswad123/mind-weaver/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "e1696de61bb665b7af8cc5fb27f8ecb328c76fb3821cf0223e759d81128a6b41"
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
