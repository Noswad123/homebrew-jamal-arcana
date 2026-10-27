# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "rbconfig"

class ArcanaTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "scripts", "arcana")
  TAP = "fixture/tools"

  def setup
    @dir = Dir.mktmpdir("arcana-test-")
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
    File.write(File.join(@bin, "brew"), "#!#{RbConfig.ruby} --disable=gems\n" + File.read(File.join(__dir__, "fixtures", "bin", "brew")))
    File.chmod(0o755, File.join(@bin, "brew"))
    File.symlink(RbConfig.ruby, File.join(@bin, "ruby"))
    # macOS system Ruby's rbconfig invokes uname even with gems disabled.
    uname = %w[/usr/bin/uname /bin/uname].find { |path| File.executable?(path) }
    File.symlink(uname, File.join(@bin, "uname")) if uname
    @manifest = { "tap" => TAP, "formulae" => [], "casks" => [] }
    @state = { "formula" => [], "cask" => [], "repo" => @dir, "failures" => [] }
    @env = {
      "PATH" => @bin, "HOME" => @dir, "ARCANA_PLATFORM" => "macos",
      "ARCANA_TOOLS_YAML" => File.join(@dir, "tools.yaml"),
      "ARCANA_UPDATE_REEXECED" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil,
      "FAKE_BREW_STATE" => File.join(@dir, "state.json"),
      "FAKE_BREW_LOG" => File.join(@dir, "brew.jsonl")
    }
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def formula(name, refresh: false, **attributes)
    { "name" => name, "reinstall_on_update" => refresh }.merge(attributes.transform_keys(&:to_s))
  end

  def package(name)
    "#{TAP}/#{name}"
  end

  def invoke(*args, script: SCRIPT)
    File.write(@env.fetch("ARCANA_TOOLS_YAML"), YAML.dump(@manifest))
    File.write(@env.fetch("FAKE_BREW_STATE"), JSON.generate(@state))
    @output, @status = Open3.capture2e(@env, RbConfig.ruby, "--disable=gems", "-x", script, *args)
    @calls = if File.exist?(@env.fetch("FAKE_BREW_LOG"))
               File.readlines(@env.fetch("FAKE_BREW_LOG")).map { |line| JSON.parse(line) }
             else
               []
             end
    @after = JSON.parse(File.read(@env.fetch("FAKE_BREW_STATE")))
  end

  def mutations
    @calls.select { |args| %w[update tap install reinstall uninstall upgrade].include?(args.first) }
  end

  def failed_entries
    @output.lines.grep(/^  FAILED /).map(&:strip)
  end

  def assert_exit(code)
    assert_equal code, @status.exitstatus, @output
  end

  def test_failed_missing_formula_and_cask_continue_refresh_and_upgrades
    @manifest["formulae"] = [formula("djinn"), formula("kitsune", refresh: true), formula("coven")]
    @manifest["casks"] = [{ "name" => "missing-app" }, { "name" => "old-app" }]
    @state.merge!("formula" => %w[kitsune coven], "cask" => ["old-app"],
                  "outdated_formula" => ["coven"], "outdated_cask" => ["old-app"])
    @state["failures"] = [["install", package("djinn")], ["install", "--cask", package("missing-app")]]
    invoke("update")
    assert_exit 1
    assert_includes mutations, ["uninstall", "--ignore-dependencies", "kitsune"]
    assert_includes mutations, ["install", package("kitsune")]
    assert_includes mutations, ["upgrade", package("coven")]
    assert_includes mutations, ["upgrade", "--cask", package("old-app")]
    assert_equal ["FAILED formula #{package('djinn')}: install/install",
                  "FAILED cask #{package('missing-app')}: install/install"], failed_entries
    assert_equal 1, mutations.count(["install", package("djinn")])
    refute_includes mutations, ["upgrade", package("djinn")]
    refute_includes mutations, ["upgrade", "--cask", package("missing-app")]
  end

  def test_ordinary_upgrade_failures_are_all_reported_once
    @manifest["formulae"] = [formula("djinn"), formula("kitsune"), formula("coven")]
    @manifest["casks"] = [{ "name" => "app" }]
    @state.merge!("formula" => %w[djinn kitsune coven], "cask" => ["app"],
                  "outdated_formula" => %w[djinn kitsune coven], "outdated_cask" => ["app"])
    @state["failures"] = [["upgrade", package("djinn")], ["upgrade", "--cask", package("app")]]
    invoke("update")
    assert_exit 1
    assert_equal ["FAILED formula #{package('djinn')}: upgrade/upgrade",
                  "FAILED cask #{package('app')}: upgrade/upgrade"], failed_entries
    assert_includes mutations, ["upgrade", package("kitsune")]
    assert_includes mutations, ["upgrade", package("coven")]
    assert_includes @output, "2 succeeded, 2 failed, 0 planned steps"
  end

  def test_refresh_uninstall_failure_skips_install_and_continues
    @manifest["formulae"] = %w[djinn kitsune coven].map { |name| formula(name, refresh: true) }
    @state["formula"] = %w[djinn kitsune coven]
    @state["failures"] = [["uninstall", "--ignore-dependencies", "djinn"]]
    invoke("update")
    assert_exit 1
    refute_includes mutations, ["install", package("djinn")]
    assert_includes mutations, ["install", package("kitsune")]
    assert_includes mutations, ["install", package("coven")]
    assert_equal ["FAILED formula #{package('djinn')}: refresh/uninstall"], failed_entries
    assert_includes @after["formula"], "djinn"
  end

  def test_refresh_install_failure_reports_previous_installation_removed
    @manifest["formulae"] = %w[djinn kitsune coven].map { |name| formula(name, refresh: true) }
    @state["formula"] = %w[djinn kitsune coven]
    @state["failures"] = [["install", package("djinn")]]
    invoke("update")
    assert_exit 1
    assert_equal ["FAILED formula #{package('djinn')}: refresh/install; previous installation removed"], failed_entries
    refute_includes @after["formula"], "djinn"
    assert_includes mutations, ["install", package("kitsune")]
    assert_includes mutations, ["install", package("coven")]
  end

  def test_initial_snapshot_excludes_new_installs_from_refresh_and_upgrade
    @manifest["formulae"] = [formula("new-refresh", refresh: true), formula("new-upgrade")]
    @manifest["casks"] = [{ "name" => "new-app" }]
    @state.merge!("outdated_formula" => %w[new-refresh new-upgrade], "outdated_cask" => ["new-app"])
    invoke("update")
    assert_exit 0
    assert_equal %w[update tap install install install], mutations.map(&:first)
    assert_includes @output, "3 succeeded, 0 failed, 0 planned steps"
  end

  def test_failed_install_is_not_retried_after_installed_snapshot_race
    @manifest["formulae"] = [formula("djinn", refresh: true), formula("djinn", refresh: true)]
    @manifest["casks"] = [{ "name" => "app" }, { "name" => "app" }]
    @state.merge!("formula" => ["djinn"], "cask" => ["app"], "outdated_cask" => ["app"],
                  "list_sequences" => { "formula:djinn" => [true, true, false, false],
                                        "cask:app" => [true, true, false, false] })
    @state["failures"] = [["install", package("djinn")], ["install", "--cask", package("app")]]
    invoke("update")
    assert_exit 1
    assert_equal %w[update tap install install], mutations.map(&:first)
    assert_equal 2, failed_entries.size
  end

  def test_successful_refresh_aliases_optional_and_platform_filters
    @manifest["formulae"] = [formula("arcana", refresh: true),
                             formula("alias", installed_name: "actual", package: "other/tap/actual", refresh: true),
                             formula("linux-only", platforms: ["linuxbrew"]),
                             formula("mac-only", platforms: ["darwin"])]
    @manifest["casks"] = [{ "name" => "other/tap/app", "installed_name" => "app", "platforms" => ["osx"] }]
    @manifest["optional"] = { "formulae" => [formula("optional", package: "optional")],
                              "casks" => [{ "name" => "optional-app", "package" => "optional-app" }] }
    @state.merge!("formula" => %w[arcana actual], "cask" => ["app"], "outdated_cask" => ["app"])
    invoke("update", "--include-optional")
    assert_exit 0
    assert_includes mutations, ["uninstall", "--ignore-dependencies", "actual"]
    assert_includes mutations, ["install", "other/tap/actual"]
    assert_includes mutations, ["install", package("mac-only")]
    assert_includes mutations, ["install", "optional"]
    assert_includes mutations, ["install", "--cask", "optional-app"]
    assert_includes mutations, ["upgrade", "--cask", "other/tap/app"]
    refute mutations.any? { |args| args.last.include?("linux-only") || args.last == package("arcana") }
    assert_empty failed_entries
  end

  def test_optional_tools_are_excluded_by_default
    @manifest["optional"] = { "formulae" => [formula("optional")], "casks" => [{ "name" => "app" }] }
    invoke("update")
    assert_exit 0
    assert_equal %w[update tap], mutations.map(&:first)
  end

  def test_no_casks_and_linux_filters
    ["--no-casks", "linux"].each do |mode|
      @manifest["formulae"] = [formula("linux-only", platforms: ["linuxbrew"]), formula("mac-only", platform: "mac")]
      @manifest["casks"] = [{ "name" => "app" }]
      @env["ARCANA_PLATFORM"] = mode == "linux" ? "linux" : "macos"
      FileUtils.rm_f(@env.fetch("FAKE_BREW_LOG"))
      invoke("update", *(mode == "--no-casks" ? [mode] : []))
      assert_exit 0
      refute mutations.any? { |args| args.include?("--cask") }
      assert_includes mutations, ["install", package(mode == "linux" ? "linux-only" : "mac-only")]
    end
  end

  def test_prerequisites_fail_fast
    [["--version"], ["update"], ["tap", TAP]].each do |failed|
      @manifest["formulae"] = [formula("djinn")]
      @state["failures"] = [failed]
      FileUtils.rm_f(@env.fetch("FAKE_BREW_LOG"))
      invoke("update")
      assert_exit 1
      refute mutations.any? { |args| %w[install upgrade uninstall].include?(args.first) }
      refute_includes @output, "Update summary:"
    end
  end

  def test_self_install_and_self_reinstall_failure_are_prerequisite_failures
    [false, true].each do |installed|
      @manifest["formulae"] = [formula("arcana"), formula("djinn")]
      @state["formula"] = installed ? ["arcana"] : []
      if installed
        FileUtils.mkdir_p(File.join(@dir, "scripts"))
        File.write(File.join(@dir, "scripts", "arcana"), "stale fixture")
      end
      @state["failures"] = [[installed ? "reinstall" : "install", package("arcana")]]
      FileUtils.rm_f(@env.fetch("FAKE_BREW_LOG"))
      invoke("update")
      assert_exit 1
      refute_includes mutations, ["install", package("djinn")]
      refute_includes @output, "Update summary:"
    end
  end

  def test_self_refresh_reexec_preserves_options_and_stops_after_one_restart
    @manifest["formulae"] = [formula("arcana"), formula("djinn")]
    @manifest["optional"] = { "formulae" => [formula("optional")] }
    @manifest["casks"] = [{ "name" => "app" }]
    @state["formula"] = ["arcana"]
    FileUtils.mkdir_p(File.join(@dir, "scripts"))
    fresh = File.read(SCRIPT) + "\n# Refreshed fixture\n"
    File.write(File.join(@dir, "scripts", "arcana"), fresh)
    current = File.join(@dir, "arcana")
    FileUtils.cp(SCRIPT, current)
    File.chmod(0o755, current)
    @state["refresh_script"] = current
    invoke("update", "--include-optional", "--no-casks", script: current)
    assert_exit 0
    assert_equal 2, mutations.count(["update"])
    assert_equal 1, mutations.count(["reinstall", package("arcana")])
    assert_equal 1, mutations.count(["install", package("optional")])
    refute mutations.any? { |args| args.include?("--cask") }
    assert_equal 1, @output.scan("Update summary:").size
  end

  def test_existing_reexec_guard_prevents_restart_even_if_still_stale
    @manifest["formulae"] = [formula("arcana"), formula("djinn")]
    @state["formula"] = ["arcana"]
    @env["ARCANA_UPDATE_REEXECED"] = "1"
    FileUtils.mkdir_p(File.join(@dir, "scripts"))
    File.write(File.join(@dir, "scripts", "arcana"), "stale fixture")
    invoke("update")
    assert_exit 0
    assert_equal 1, mutations.count(["update"])
    assert_includes mutations, ["install", package("djinn")]
  end

  def test_standalone_install_and_self_update_remain_fail_fast
    %w[install self-update].each do |command|
      @manifest["formulae"] = [formula("arcana"), formula("djinn"), formula("kitsune")]
      @state["failures"] = [["install", package("arcana")]]
      FileUtils.rm_f(@env.fetch("FAKE_BREW_LOG"))
      invoke(command)
      assert_exit 1
      refute_includes mutations, ["install", package("djinn")]
      refute_includes mutations, ["install", package("kitsune")]
      refute_includes @output, "Update summary:"
    end
  end

  def test_dry_run_reports_planned_steps_without_mutations_or_success_claims
    @manifest["formulae"] = [formula("djinn"), formula("kitsune", refresh: true), formula("coven")]
    @manifest["casks"] = [{ "name" => "app" }]
    @state.merge!("formula" => %w[kitsune coven], "cask" => ["app"],
                  "outdated_formula" => ["coven"], "outdated_cask" => ["app"])
    invoke("update", "--dry-run")
    assert_exit 0
    assert_empty mutations
    assert_equal @state, @after
    assert_includes @output, "0 succeeded, 0 failed, 5 planned steps"
    refute_includes @output, "Install state:"
    assert_empty failed_entries
  end

  def test_dry_run_without_brew_is_safe
    FileUtils.rm(File.join(@bin, "brew"))
    @manifest["formulae"] = [formula("kitsune", refresh: true)]
    invoke("update", "--dry-run")
    assert_exit 0
    assert_empty @calls
    assert_includes @output, "0 succeeded, 0 failed, 1 planned steps"
  end

  def test_mixed_failures_are_all_summarized_once_with_later_successes
    @manifest["formulae"] = [formula("djinn"), formula("bad-remove", refresh: true),
                             formula("bad-install", refresh: true), formula("old"),
                             formula("kitsune", refresh: true), formula("coven")]
    @manifest["casks"] = [{ "name" => "missing-app" }, { "name" => "old-app" }]
    @state.merge!("formula" => %w[bad-remove bad-install old kitsune coven], "cask" => ["old-app"],
                  "outdated_formula" => %w[old coven], "outdated_cask" => ["old-app"])
    @state["failures"] = [["install", package("djinn")], ["install", "--cask", package("missing-app")],
                          ["uninstall", "--ignore-dependencies", "bad-remove"],
                          ["install", package("bad-install")], ["upgrade", package("old")],
                          ["upgrade", "--cask", package("old-app")]]
    invoke("update")
    assert_exit 1
    assert_equal ["FAILED formula #{package('djinn')}: install/install",
                  "FAILED cask #{package('missing-app')}: install/install",
                  "FAILED formula #{package('bad-remove')}: refresh/uninstall",
                  "FAILED formula #{package('bad-install')}: refresh/install; previous installation removed",
                  "FAILED formula #{package('old')}: upgrade/upgrade",
                  "FAILED cask #{package('old-app')}: upgrade/upgrade"], failed_entries
    assert_includes @output, "4 succeeded, 6 failed, 0 planned steps"
    assert_equal 1, @output.scan("Update summary:").size
    assert_includes mutations, ["install", package("kitsune")]
    assert_includes mutations, ["upgrade", package("coven")]
  end

  def test_reexec_failure_stops_before_package_phase
    @manifest["formulae"] = [formula("arcana"), formula("djinn")]
    @state["formula"] = ["arcana"]
    FileUtils.mkdir_p(File.join(@dir, "scripts"))
    File.write(File.join(@dir, "scripts", "arcana"), "#!/nonexistent-arcana-fixture\n")
    current = File.join(@dir, "arcana")
    FileUtils.cp(SCRIPT, current)
    File.chmod(0o755, current)
    @state["refresh_script"] = current
    invoke("update", script: current)
    assert_exit 1
    assert_includes mutations, ["reinstall", package("arcana")]
    refute_includes mutations, ["install", package("djinn")]
    refute_includes @output, "Update summary:"
  end
end
