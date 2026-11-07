require "shellwords"

class Coven < Formula
  desc "Magic-themed multi-agent workspaces backed by local files and kitsune"
  homepage "https://github.com/Noswad123/coven"
  url "https://github.com/Noswad123/coven.git", branch: "main"
  version "0.1.0-dev"
  license "MIT"
  revision 1

  depends_on "kitsune"
  depends_on "python@3.13"

  def install
    libexec.install "bin", "runner", "examples", "README.md", "LICENSE"
    (bin/"coven").write <<~SH
      #!/bin/sh
      default_home=#{Shellwords.escape(opt_libexec.to_s)}
      default_command=#{Shellwords.escape((opt_bin/"coven").to_s)}
      : "${COVEN_HOME:=$default_home}"
      : "${COVEN_COMMAND:=${ARCANA_PUBLIC_COVEN:-$default_command}}"
      export COVEN_HOME COVEN_COMMAND
      exec #{Shellwords.escape((Formula["python@3.13"].opt_bin/"python3.13").to_s)} "$COVEN_HOME/runner/coven.py" "$@"
    SH
    (bin/"coven").chmod 0755
  end

  def caveats
    <<~EOS
      coven launches workspaces through kitsune by default.

      tmux can still be used by coven configurations that target the legacy
      tmux runner; install tmux separately if you use that backend.
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
