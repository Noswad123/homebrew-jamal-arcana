class Arcana < Formula
  desc "Install and update the Jamal Arcana Homebrew ecosystem"
  homepage "https://github.com/Noswad123/homebrew-jamal-arcana"
  url "https://github.com/Noswad123/homebrew-jamal-arcana.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  def install
    bin.install "scripts/arcana"
    pkgshare.install "tools.yaml", "Formula", "Casks"
  end

  test do
    assert_match "Tap: Noswad123/jamal-arcana", shell_output("#{bin}/arcana list")
  end
end
