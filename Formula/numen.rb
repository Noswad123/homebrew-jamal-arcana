class Numen < Formula
  desc "Event-driven desktop familiar for the Arcana ecosystem"
  homepage "https://github.com/Noswad123/numen"
  url "https://github.com/Noswad123/numen.git", branch: "main"
  version "0.1.0-dev"

  depends_on :macos
  depends_on "rust" => :build

  def install
    system "cargo", "install", *std_cargo_args
  end

  def caveats
    <<~EOS
      Launch the familiar manually with:
        numen run

      A graphical desktop is required. No service or autostart is installed.
      Validate the embedded artwork without opening a window with:
        numen check-assets
    EOS
  end

  test do
    assert_match "numen", shell_output("#{bin}/numen --version")
    output = shell_output("#{bin}/numen check-assets")
    assert_match "validated embedded RGBA atlas", output
    assert_match "running-right", output
  end
end
