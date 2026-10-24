class Mw < Formula
  desc "Local-first Rust notes and todos CLI"
  homepage "https://github.com/Noswad123/mind-weaver"
  # Package the Rust migration without inventing an upstream release tag. Keep
  # the previous package baseline so revision 1 upgrades installed Go 0.1.3.
  url "https://github.com/Noswad123/mind-weaver/archive/4745d03ac750c45ae52f63b736620fdc617b0541.tar.gz"
  version "0.1.3"
  sha256 "8290c19c9845e0d1c3020c188fb93b53b4b06217658bbf5682c7b41dd32053bd"
  license "MIT"
  revision 1
  head "https://github.com/Noswad123/mind-weaver.git", branch: "main"

  depends_on "rust" => :build

  def install
    # std_cargo_args enforces Cargo.lock with --locked. SQLite is bundled by the
    # upstream workspace; no separate Go toolchain or SQLite service is needed.
    system "cargo", "install", *std_cargo_args(path: "crates/mw")
  end

  def caveats
    <<~EOS
      This package replaces the Go CLI with a pinned Rust migration preview.
      Homebrew package 0.1.3_1 reports upstream Rust CLI version 0.1.0.

      Compatibility is incomplete: Hive Sync (`mw sync`, including remote
      push/pull and token/conflict workflows) is not supported by this Rust
      snapshot. `mw seal` is a local notes pipeline, not a remote-sync replacement.
      Do not migrate a workflow that depends on Hive Sync to this preview.

      `mw todos snapshot --json` and task-safety-v1 are also not implemented.
      Updating this package alone does not enable integrations requiring them.
      No notes/database migration or legacy-Go fallback is run automatically.
    EOS
  end

  test do
    require "json"

    assert_match "MindWeaver Rust port", shell_output("#{bin}/mw --help")
    # Cargo's version is currently 0.1.0, independent of Homebrew's 0.1.3_1
    # migration baseline. Do not inject a fake upstream release version.
    cli_version = shell_output("#{bin}/mw version --short").strip
    assert_match(/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/, cli_version)
    assert_equal "mw #{cli_version}", shell_output("#{bin}/mw --version").strip

    # Machine-readable APIs must work against an isolated config without
    # creating a database, notes, or a dashboard. Never read a user's notes.
    ENV["MW_CONFIG"] = testpath/"config.toml"
    ENV["NOTES_DIR"] = testpath/"notes"
    ENV["NOTES_DB_PATH"] = testpath/"must-not-create/notes.db"
    ENV["INBOX_PATH"] = testpath/"notes/inbox.md"
    ENV["MW_INBOX_PATH"] = testpath/"notes/inbox.md"
    ENV["DASHBOARD_PATH"] = testpath/"notes/dashboard.md"
    (testpath/"config.toml").write <<~TOML
      notes_dir = #{ENV.fetch("NOTES_DIR").to_json}
      db_path = #{ENV.fetch("NOTES_DB_PATH").to_json}
      inbox_path = #{ENV.fetch("MW_INBOX_PATH").to_json}
      dashboard_path = #{ENV.fetch("DASHBOARD_PATH").to_json}
    TOML

    config = JSON.parse(shell_output("#{bin}/mw config json"))
    assert_equal "1", config.fetch("schemaVersion")
    assert_equal ENV.fetch("NOTES_DIR"), config.fetch("notesDir")
    assert_equal ENV.fetch("MW_INBOX_PATH"), config.fetch("inboxPath")
    assert_equal ENV.fetch("DASHBOARD_PATH"), config.fetch("dashboardPath")
    schemas = JSON.parse(shell_output("#{bin}/mw schema list --json"))
    assert_equal "1", schemas.fetch("schemaVersion")
    assert_kind_of Array, schemas.fetch("schemas")
    refute_empty schemas.fetch("schemas")
    refute_path_exists testpath/"must-not-create"
    refute_path_exists testpath/"notes"
  end
end
