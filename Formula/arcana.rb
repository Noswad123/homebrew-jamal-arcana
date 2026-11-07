class Arcana < Formula
  desc "Install and update the Jamal Arcana Homebrew ecosystem"
  homepage "https://github.com/Noswad123/homebrew-jamal-arcana"
  url "https://github.com/Noswad123/homebrew-jamal-arcana.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  on_linux do
    depends_on "ruby"
  end

  def install
    bin.install "scripts/arcana"
    pkgshare.install "tools.yaml", "Formula", "Casks"
    pkgshare.install "scripts/arcana-source.rb", "scripts/arcana-dispatch.rb"
  end

  test do
    assert_match "Tap: Noswad123/jamal-arcana", shell_output("#{bin}/arcana list")
    assert_match "Usage: arcana source", shell_output("#{bin}/arcana source --help")
  end
end
