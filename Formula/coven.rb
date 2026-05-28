class Coven < Formula
  desc "Magic-themed multi-agent workspaces backed by local files and tmux"
  homepage "https://github.com/Noswad123/coven"
  url "https://github.com/Noswad123/coven.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"

  depends_on "python@3.13"
  depends_on "tmux"

  def install
    libexec.install "bin", "runner", "examples", "README.md", "LICENSE"
    bin.write_exec_script libexec/"bin/coven"
  end

  def caveats
    <<~EOS
      coven launches tmux workspaces through the existing `tmux` runner.
    EOS
  end

  test do
    assert_match "Manage multi-agent coven workspaces", shell_output("#{bin}/coven --help")

    workspace = testpath/"test-coven"
    system bin/"coven", "init", workspace, "--blank", "--agents", "orchestrator,architect"
    assert_path_exists workspace/"coven.json"
    assert_path_exists workspace/"state/tasks.json"
    assert_path_exists workspace/"tmux/coven.toml"
  end
end
