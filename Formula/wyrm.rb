class Wyrm < Formula
  desc "Dragon-hoard terminal file manager for local files"
  homepage "https://github.com/Noswad123/wyrm"
  url "https://github.com/Noswad123/wyrm.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  depends_on "go" => :build

  def install
    system "go", "build", "-o", bin/"wyrm", "."
  end

  test do
    assert_match "Usage: wyrm", shell_output("#{bin}/wyrm --help")
  end
end
