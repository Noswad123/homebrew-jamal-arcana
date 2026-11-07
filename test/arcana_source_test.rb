# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "json"
require "yaml"
require "timeout"

# All subprocesses have a private home, manifest, PATH, state, and payloads.
# In particular, no test can discover the developer's brew or applications.
class ArcanaSourceTest < Minitest::Test
  SCRIPTS = File.expand_path("../scripts", __dir__)

  def setup
    @tmp = Dir.mktmpdir("arcana source tests ")
    @home = File.join(@tmp, "home")
    @state_home = File.join(@tmp, "state with spaces")
    @bin = File.join(@tmp, "launchers with spaces")
    @dev = File.join(@tmp, "development root")
    @brew = File.join(@tmp, "brew prefix")
    @path = File.join(@tmp, "fake path")
    @cwd = File.join(@tmp, "working directory")
    @manifest = File.join(@tmp, "tools.yaml")
    @brew_log = File.join(@tmp, "brew calls.jsonl")
    @trap_log = File.join(@tmp, "unexpected path command")
    [@home, @path, @cwd].each { |path| FileUtils.mkdir_p(path) }
    # Apple's Ruby 2.6 rbconfig shells out to uname even with gems disabled.
    # Expose only that utility, not a system PATH containing real applications.
    File.symlink("/usr/bin/uname", File.join(@path, "uname")) if File.executable?("/usr/bin/uname")
    @env = {
      "HOME" => @home, "XDG_STATE_HOME" => @state_home,
      "ARCANA_BIN_DIR" => @bin, "ARCANA_TOOLS_YAML" => @manifest,
      "ARCANA_PLATFORM" => "linux", "PATH" => @path,
      "BREW_PREFIX" => @brew, "BREW_LOG" => @brew_log,
      "TRAP_LOG" => @trap_log, "PROBE_VALUE" => "inherited value"
    }
    @data = {
      "tap" => "fixture/arcana",
      "formulae" => [
        { "name" => "alpha", "installed_name" => "alpha-installed", "platforms" => ["linux"],
          "sources" => { "commands" => %w[alpha alpha-extra], "aliases" => ["a"],
                         "companions" => [{ "command" => "alpha-helper", "platforms" => ["linux"] }],
                         "environment" => { "ALPHA_HELPER" => "alpha-helper" } } },
        { "name" => "mac-only", "platforms" => ["macos"],
          "sources" => { "commands" => ["mac-command"] } },
        { "name" => "unregistered", "command" => "not-sourceable" }
      ],
      "optional" => { "formulae" => [
        { "name" => "beta", "platforms" => ["linux", "macos"],
          "sources" => { "commands" => ["beta"], "aliases" => ["b"],
                         "companions" => [{ "command" => "beta-linux", "platforms" => ["linuxbrew"] }] } }
      ] }
    }
    write_manifest
    executable(File.join(@path, "brew"), <<~RUBY)
      #!#{RbConfig.ruby} --disable=gems
      require "json"
      File.open(ENV.fetch("BREW_LOG"), "a") { |f| f.puts(JSON.generate(ARGV)) }
      abort "only brew --prefix is permitted" unless ARGV == ["--prefix"]
      puts ENV.fetch("BREW_PREFIX")
    RUBY
    %w[ruby alpha alpha-extra beta alpha-helper].each do |name|
      executable(File.join(@path, name), "#!/bin/sh\nprintf '%s\\n' unexpected >> \"$TRAP_LOG\"\nexit 97\n")
    end
    make_payloads("dev")
    make_payloads("brew")
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp && File.exist?(@tmp)
  end

  def write_manifest
    File.write(@manifest, YAML.dump(@data))
  end

  def executable(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(0o755, path)
  end

  def target(source, app, command, root = nil)
    root ||= source == "dev" ? @dev : @brew
    installed = app == "alpha" ? "alpha-installed" : app
    source == "dev" ? File.join(root, app, "bin", command) : File.join(root, "opt", installed, "bin", command)
  end

  def make_payloads(source, root = nil)
    { "alpha" => %w[alpha alpha-extra alpha-helper],
      "beta" => %w[beta beta-linux], "mac-only" => ["mac-command"] }.each do |app, commands|
      commands.each do |command|
        executable(target(source, app, command, root), <<~RUBY)
          #!#{RbConfig.ruby} --disable=gems
          require "json"
          puts JSON.generate("payload" => #{"#{source}/#{app}/#{command}".dump},
                             "argv" => ARGV, "cwd" => Dir.pwd,
                             "helper" => ENV["ALPHA_HELPER"], "value" => ENV["PROBE_VALUE"])
          warn "payload stderr" if ENV["PROBE_STDERR"]
          exit Integer(ENV.fetch("PROBE_EXIT", "0"))
        RUBY
      end
    end
  end

  def cli(*args, env: {}, script: File.join(SCRIPTS, "arcana"))
    capture([RbConfig.ruby, "--disable=gems", "-x", script, "source", *args], env)
  end

  def capture(argv, env = {})
    Open3.capture3(@env.merge(env), [argv.first, argv.first], *argv.drop(1),
                   chdir: @cwd, unsetenv_others: true)
  end

  def launch(command, *args, env: {})
    capture([File.join(@bin, command), *args], env)
  end

  def success(result)
    out, err, status = result
    assert status.success?, "exit #{status.exitstatus}: #{out}\n#{err}"
    out
  end

  def failure(result, code = 1, pattern = nil)
    out, err, status = result
    assert_equal code, status.exitstatus, "#{out}\n#{err}"
    assert_match pattern, out + err if pattern
    refute File.exist?(@trap_log), "a PATH fallback was executed"
    out + err
  end

  def select(source, *apps, root: nil)
    option = source == "dev" ? "--dev-root" : "--brew-prefix"
    cli("use", source, *apps, option, root || (source == "dev" ? @dev : @brew))
  end

  def state_path
    File.join(@state_home, "arcana", "sources.json")
  end

  def state
    JSON.parse(File.read(state_path))
  end

  # Include directories, symlinks (even broken ones), modes, and timestamps so
  # read-only assertions also catch creating a lock or rewriting identical data.
  def snapshot
    [@home, @state_home, @bin].each_with_object({}) do |root, result|
      paths = [root] + Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)
      paths.reject { |path| %w[. ..].include?(File.basename(path)) }.sort.each do |path|
        next unless File.exist?(path) || File.symlink?(path)
        stat = File.lstat(path)
        content = if stat.symlink?
                    File.readlink(path)
                  elsif stat.file?
                    File.binread(path)
                  end
        result[path] = [stat.ftype, stat.mode, stat.ino, stat.mtime, content]
      end
    end
  end

  def assert_no_brew
    refute File.exist?(@brew_log), "unexpected brew invocation"
  end

  # Hooks live only in a child process; the actual CLI and core stay unchanged.
  def with_injected_cli(hook, *args, env: {}, script: File.join(SCRIPTS, "arcana"))
    @hook_count = (@hook_count || 0) + 1
    path = File.join(@tmp, "hook-#{@hook_count}.rb")
    File.write(path, <<~RUBY + hook)
      module ArcanaTestBarrier
        def self.pause
          File.write(ENV.fetch("TEST_READY"), "ready")
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
          until File.exist?(ENV.fetch("TEST_RELEASE"))
            raise IOError, "test barrier timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            sleep 0.01
          end
        end
      end
    RUBY
    Open3.popen3(@env.merge(env), RbConfig.ruby, "--disable=gems", "-r", path,
                 "-x", script, "source", *args, chdir: @cwd, unsetenv_others: true) do |input, out, err, child|
      input.close
      begin
        yield out, err, child
      ensure
        if child.alive?
          Process.kill("KILL", child.pid) rescue Errno::ESRCH
          child.join
        end
      end
    end
  end

  def wait_for_barrier(path, child, err = nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until File.exist?(path)
      flunk "child exited before reaching #{File.basename(path)}: #{err.read if err}" unless child.alive?
      flunk "timed out waiting for #{File.basename(path)}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
  end

  def child_result(out, err, child)
    Timeout.timeout(10) { [out.read, err.read, child.value] }
  end

  def test_one_alias_provisions_bundle_and_same_selection_can_be_retried
    success(select("dev", "a", "alpha"))
    assert_equal ["alpha"], state.fetch("apps").keys
    app = state["apps"]["alpha"]
    assert_equal "dev", app["source"]
    assert_equal %w[alpha alpha-extra], app["commands"].keys.sort
    assert_equal({ "alpha-helper" => target("dev", "alpha", "alpha-helper") }, app["companions"])
    assert_equal({ "ALPHA_HELPER" => target("dev", "alpha", "alpha-helper") }, app["environment"])
    refute File.exist?(File.join(@bin, "alpha-helper"))
    %w[alpha alpha-extra].each do |command|
      assert File.executable?(File.join(@bin, command))
      probe = JSON.parse(success(launch(command)))
      assert_equal "dev/alpha/#{command}", probe["payload"]
      assert_equal target("dev", "alpha", "alpha-helper"), probe["helper"]
    end
    original = state
    success(select("dev", "alpha"))
    assert_equal original, state
    assert_no_brew
  end

  def test_multiple_apps_and_switch_preserve_unrequested_selection_and_launchers
    success(select("dev", "a", "b"))
    beta = state["apps"]["beta"]
    beta_launcher = File.binread(File.join(@bin, "beta"))
    success(select("brew", "alpha"))
    assert_equal beta, state["apps"]["beta"]
    assert_equal beta_launcher, File.binread(File.join(@bin, "beta"))
    assert_equal "brew/alpha/alpha", JSON.parse(success(launch("alpha")))["payload"]
    assert_equal "dev/beta/beta", JSON.parse(success(launch("beta")))["payload"]
    assert_no_brew
  end

  def test_all_filters_apps_and_platform_specific_companions_including_optional_apps
    success(select("dev", "--all"))
    assert_equal %w[alpha beta], state["apps"].keys.sort
    assert_equal ["beta-linux"], state["apps"]["beta"]["companions"].keys
    refute File.exist?(File.join(@bin, "mac-command"))
    assert_no_brew
  end

  def test_platform_aliases_and_companion_filtering_on_macos
    success(cli("use", "dev", "--all", "--dev-root", @dev, env: { "ARCANA_PLATFORM" => "darwin" }))
    assert_equal %w[beta mac-only], state["apps"].keys.sort
    assert_empty state["apps"]["beta"]["companions"]
    assert_no_brew
  end

  def test_brew_discovery_only_requests_prefix_and_runtime_does_not_consult_brew
    success(cli("use", "brew", "alpha"))
    assert_equal [["--prefix"]], File.readlines(@brew_log).map { |line| JSON.parse(line) }
    assert_equal target("brew", "alpha", "alpha"), state["apps"]["alpha"]["commands"]["alpha"]
    File.unlink(@brew_log)
    success(launch("alpha"))
    before = snapshot
    success(cli("status"))
    success(cli("doctor"))
    assert_equal before, snapshot
    assert_no_brew
  end

  def test_linux_platform_alias_supports_app_and_companions
    success(cli("use", "dev", "b", "--dev-root", @dev, env: { "ARCANA_PLATFORM" => "linuxbrew" }))
    assert_equal ["beta"], state["apps"].keys
    assert_equal ["beta-linux"], state["apps"]["beta"]["companions"].keys
    success(launch("beta"))
    assert_no_brew
  end

  def test_all_with_no_supported_apps_fails_without_writes
    before = snapshot
    failure(cli("use", "dev", "--all", "--dev-root", @dev,
                env: { "ARCANA_PLATFORM" => "unsupported-os" }), 2, /empty.*selection/)
    assert_equal before, snapshot
    assert_no_brew
  end

  def test_source_help_is_read_only
    before = snapshot
    [["--help"], %w[use --help], %w[status --help], %w[doctor --help]].each do |args|
      assert_match(/Usage: arcana source/, success(cli(*args)))
      assert_equal before, snapshot
    end
    assert_no_brew
  end

  def test_default_dev_root
    root = File.join(@home, ".local", "libexec", "arcana-dev")
    make_payloads("dev", root)
    success(cli("use", "dev", "alpha"))
    assert_equal target("dev", "alpha", "alpha", root), state["apps"]["alpha"]["commands"]["alpha"]
    success(launch("alpha"))
    assert_no_brew
  end

  def test_arguments_cwd_environment_stderr_and_exit_survive_minimal_misleading_path
    success(select("dev", "alpha"))
    args = ["two words", "", "'quoted'", "$(touch nope)", "--flag=value", "line\nbreak"]
    out, err, status = launch("alpha-extra", *args,
                              env: { "ALPHA_HELPER" => "explicit override", "PROBE_EXIT" => "23", "PROBE_STDERR" => "1" })
    assert_equal 23, status.exitstatus, err
    probe = JSON.parse(out)
    assert_equal args, probe["argv"]
    assert_equal File.realpath(@cwd), probe["cwd"]
    assert_equal "explicit override", probe["helper"]
    assert_equal "inherited value", probe["value"]
    assert_equal "payload stderr\n", err
    assert_equal "", JSON.parse(success(launch("alpha", env: { "ALPHA_HELPER" => "" })))["helper"]
    refute File.exist?(@trap_log)
    assert_no_brew
  end

  [false, true].each do |all|
    define_method("test_missing_target_aborts_#{all ? 'all' : 'batch'}_without_any_writes") do
      File.unlink(target("dev", "beta", "beta"))
      before = snapshot
      args = all ? ["--all"] : %w[alpha beta]
      failure(select("dev", *args), 1, /beta.*missing|missing.*beta/)
      assert_equal before, snapshot
      assert_no_brew
    end
  end

  def test_failed_switch_preserves_prior_state_and_retry_after_repair_works
    success(select("dev", "alpha", "beta"))
    path = target("brew", "beta", "beta-linux")
    content = File.read(path)
    File.unlink(path)
    before = snapshot
    failure(select("brew", "alpha", "beta"), 1, /beta-linux/)
    assert_equal before, snapshot
    assert_equal "dev/alpha/alpha", JSON.parse(success(launch("alpha")))["payload"]
    executable(path, content)
    success(select("brew", "alpha", "beta"))
    assert state["apps"].values.all? { |app| app["source"] == "brew" }
    assert_no_brew
  end

  %w[regular symlink broken_symlink].each do |kind|
    define_method("test_unmanaged_#{kind}_is_never_replaced") do
      path = File.join(@bin, "alpha-extra")
      FileUtils.mkdir_p(@bin)
      if kind == "regular"
        executable(path, "#!/bin/sh\nexit 0\n")
      else
        destination = kind == "symlink" ? target("dev", "alpha", "alpha-extra") : File.join(@tmp, "absent")
        File.symlink(destination, path)
      end
      before = snapshot
      failure(select("dev", "alpha", "beta"), 1, /unmanaged|refus/i)
      assert_equal before, snapshot
      assert_no_brew
    end
  end

  def test_dry_run_validates_without_creating_state_lock_runtime_or_launchers
    before = snapshot
    assert_match(/Would select/, success(select("dev", "alpha", "--dry-run")))
    assert_equal before, snapshot
    success(select("dev", "alpha"))
    before = snapshot
    success(select("brew", "alpha", "--dry-run"))
    assert_equal before, snapshot
    File.unlink(target("brew", "alpha", "alpha-helper"))
    failure(select("brew", "alpha", "--dry-run"), 1, /alpha-helper/)
    assert_equal before, snapshot
    assert_no_brew
  end

  {
    "missing_subcommand" => [], "unknown_subcommand" => ["wat"],
    "missing_source" => ["use"], "wrong_source" => %w[use local alpha],
    "missing_selection" => %w[use dev], "mixed_selection" => %w[use dev alpha --all],
    "unknown_app" => %w[use dev absent], "unregistered_app" => %w[use dev unregistered],
    "reserved_app" => %w[use dev arcana],
    "unsupported_app" => %w[use dev mac-only], "unknown_flag" => %w[use dev alpha --wat],
    "abbreviated_flag" => %w[use dev alpha --dry], "wrong_brew_root" => %w[use dev alpha --brew-prefix /tmp],
    "wrong_dev_root" => %w[use brew alpha --dev-root /tmp],
    "relative_dev_root" => %w[use dev alpha --dev-root relative],
    "relative_brew_root" => %w[use brew alpha --brew-prefix relative],
    "status_argument" => %w[status alpha], "doctor_argument" => %w[doctor alpha],
    "status_flag" => %w[status --all], "doctor_flag" => %w[doctor --dry-run]
  }.each do |name, args|
    define_method("test_rejects_#{name}_without_writes") do
      before = snapshot
      failure(cli(*args), 2)
      assert_equal before, snapshot
      assert_no_brew
    end
  end

  %w[XDG_STATE_HOME ARCANA_BIN_DIR].each do |key|
    define_method("test_rejects_relative_#{key.downcase}") do
      before = snapshot
      failure(cli("use", "dev", "alpha", env: { key => "relative" }), 2, /absolute/)
      assert_equal before, snapshot
      assert_no_brew
    end
  end

  {
    "json" => "{broken", "version" => JSON.generate("version" => 2, "apps" => {}),
    "structure" => JSON.generate("version" => 1, "apps" => []),
    "registration" => JSON.generate("version" => 1, "apps" => { "alpha" => { "source" => "dev" } })
  }.each do |kind, content|
    define_method("test_corrupt_state_#{kind}_is_read_only_for_selection_and_diagnostics") do
      FileUtils.mkdir_p(File.dirname(state_path))
      File.write(state_path, content)
      before = snapshot
      [%w[use brew alpha], ["status"], ["doctor"]].each do |args|
        failure(cli(*args), 1, /state|registration/)
        assert_equal before, snapshot
      end
      assert_no_brew
    end
  end

  def test_runtime_rejects_corrupted_state_without_executing_payload
    success(select("dev", "alpha"))
    File.write(state_path, "{broken")
    before = snapshot
    output = failure(launch("alpha"), 1, /arcana source: invalid source state JSON/)
    assert_match(/doctor/, output)
    refute_match(/from .*:\d+|JSON::ParserError|Traceback/, output)
    assert_equal before, snapshot
    assert_no_brew
  end

  def test_corrupted_runtime_is_rejected_by_launcher_and_doctor
    success(select("dev", "alpha"))
    runtime = state["apps"]["alpha"]["runtime"]
    File.open(runtime, "a") { |file| file.puts("raise 'must not load modified runtime'") }
    before = snapshot
    failure(launch("alpha"), 1, /dispatcher|runtime/i)
    failure(cli("doctor"), 1, /dispatcher|runtime/i)
    assert_equal before, snapshot
    assert_no_brew
  end

  def test_missing_selected_payload_does_not_fall_back_to_other_source_or_path
    success(select("dev", "alpha"))
    File.unlink(target("dev", "alpha", "alpha"))
    before = snapshot
    output = failure(launch("alpha"), 1, /missing|non-executable/)
    refute_match(/"payload"/, output)
    assert_equal before, snapshot
    assert_no_brew
  end

  def test_runtime_checks_missing_helper_even_when_invoking_another_bundle_command
    success(select("dev", "alpha"))
    File.unlink(target("dev", "alpha", "alpha-helper"))
    before = snapshot
    failure(launch("alpha-extra", env: { "ALPHA_HELPER" => "override" }), 1, /alpha-helper/)
    assert_equal before, snapshot
    assert_no_brew
  end

  def test_nonexecutable_target_rejected_before_publication
    File.chmod(0o644, target("dev", "alpha", "alpha-extra"))
    before = snapshot
    failure(select("dev", "alpha"), 1, /non-executable/)
    assert_equal before, snapshot
    assert_no_brew
  end

  def test_target_pointing_to_another_launcher_is_rejected_at_selection_and_runtime
    success(select("dev", "beta"))
    path = target("dev", "alpha", "alpha")
    original = File.read(path)
    File.unlink(path)
    File.symlink(File.join(@bin, "beta"), path)
    before = snapshot
    failure(select("dev", "alpha"), 1, /recursive/)
    assert_equal before, snapshot
    File.unlink(path)
    executable(path, original)
    success(select("dev", "alpha"))
    File.unlink(path)
    File.symlink(File.join(@bin, "beta"), path)
    before = snapshot
    failure(launch("alpha"), 1, /recursive/)
    assert_equal before, snapshot
    assert_no_brew
  end

  def copy_checkout
    checkout = File.join(@tmp, "temporary checkout")
    FileUtils.mkdir_p(File.join(checkout, "scripts"))
    %w[arcana arcana-source.rb arcana-dispatch.rb].each do |name|
      FileUtils.cp(File.join(SCRIPTS, name), File.join(checkout, "scripts", name))
    end
    FileUtils.cp(@manifest, File.join(checkout, "tools.yaml"))
    checkout
  end

  def test_launchers_survive_checkout_removal
    checkout = copy_checkout
    success(cli("use", "dev", "alpha", "--dev-root", @dev,
                script: File.join(checkout, "scripts", "arcana"),
                env: { "ARCANA_TOOLS_YAML" => File.join(checkout, "tools.yaml") }))
    FileUtils.remove_entry(checkout)
    File.unlink(@manifest)
    assert_equal "dev/alpha/alpha", JSON.parse(success(launch("alpha")))["payload"]
    assert_no_brew
  end

  def test_reselect_after_runtime_update_does_not_treat_owned_launcher_as_unmanaged
    checkout = copy_checkout
    script = File.join(checkout, "scripts", "arcana")
    args = ["use", "dev", "alpha", "--dev-root", @dev]
    success(cli(*args, script: script))
    launchers = state["apps"]["alpha"]["launchers"].values
    original = launchers.map { |path| [File.binread(path), File.stat(path).ino, File.stat(path).mtime] }
    old_runtime = state["apps"]["alpha"]["runtime"]
    File.open(File.join(checkout, "scripts", "arcana-dispatch.rb"), "a") do |file|
      file.puts("\n# Fixture runtime update.")
    end
    success(cli(*args, script: script))
    refute_equal old_runtime, state["apps"]["alpha"]["runtime"]
    assert_equal original, launchers.map { |path| [File.binread(path), File.stat(path).ino, File.stat(path).mtime] }
    File.unlink(old_runtime)
    success(launch("alpha"))
    success(cli("doctor", script: script))
    assert_no_brew
  end

  %w[linux macos].each do |platform|
    define_method("test_platform_companion_environment_and_overrides_on_#{platform}") do
      alpha = @data["formulae"].first
      alpha.delete("platforms")
      source = alpha["sources"]
      source.delete("environment")
      source["companions"].first["environment"] = "ALPHA_HELPER"
      source["companions"] << { "command" => "alpha-mac-helper", "platforms" => ["macos"],
                                 "environment" => "ALPHA_HELPER" }
      write_manifest
      command = platform == "linux" ? "alpha-helper" : "alpha-mac-helper"
      inactive = platform == "linux" ? "alpha-mac-helper" : "alpha-helper"
      %w[dev brew].each do |selected|
        helper = target(selected, "alpha", command)
        executable(helper, "#!/bin/sh\nexit 0\n")
        FileUtils.rm_f(target(selected, "alpha", inactive))
        option = selected == "dev" ? "--dev-root" : "--brew-prefix"
        root = selected == "dev" ? @dev : @brew
        success(cli("use", selected, "alpha", option, root, env: { "ARCANA_PLATFORM" => platform }))
        app = state["apps"]["alpha"]
        assert_equal({ command => helper }, app["companions"])
        assert_equal({ "ALPHA_HELPER" => helper }, app["environment"])
        assert_equal helper, JSON.parse(success(launch("alpha")))["helper"]
        ["caller supplied helper", ""].each do |override|
          assert_equal override, JSON.parse(success(launch("alpha", env: { "ALPHA_HELPER" => override })))["helper"]
        end
      end
      assert_no_brew
    end
  end

  def test_symlinked_dev_command_uses_selected_dev_helper_not_realpath_sibling
    source = @data["formulae"].first["sources"]
    source.delete("environment")
    source["companions"].first["environment"] = "ALPHA_HELPER"
    write_manifest
    path = target("dev", "alpha", "alpha")
    File.unlink(path)
    File.symlink(target("brew", "alpha", "alpha"), path)
    success(select("dev", "alpha"))
    probe = JSON.parse(success(launch("alpha")))
    assert_equal "brew/alpha/alpha", probe["payload"]
    assert_equal target("dev", "alpha", "alpha-helper"), probe["helper"]
    assert_no_brew
  end

  def test_inactive_companion_does_not_require_target_or_inject_environment
    alpha = @data["formulae"].first
    alpha.delete("platforms")
    source = alpha["sources"]
    source.delete("environment")
    source["companions"].first["environment"] = "ALPHA_HELPER"
    write_manifest
    File.unlink(target("dev", "alpha", "alpha-helper"))
    success(cli("use", "dev", "alpha", "--dev-root", @dev, env: { "ARCANA_PLATFORM" => "macos" }))
    assert_empty state["apps"]["alpha"]["companions"]
    assert_empty state["apps"]["alpha"]["environment"]
    assert_nil JSON.parse(success(launch("alpha")))["helper"]
    assert_equal "explicit", JSON.parse(success(launch("alpha", env: { "ALPHA_HELPER" => "explicit" })))["helper"]
    assert_no_brew
  end

  {
    "companion_nonstring" => 17, "companion_empty" => "", "companion_invalid" => "BAD-NAME",
    "companion_null" => nil, "companion_duplicate_mapping" => "ALPHA_HELPER",
    "companion_duplicate_active" => "SHARED_HELPER", "mapping_invalid" => "BAD-NAME",
    "mapping_unknown_command" => "UNKNOWN_COMMAND"
  }.each do |kind, value|
    define_method("test_registry_rejects_#{kind}_without_backtrace_or_writes") do
      source = @data["formulae"].first["sources"]
      if kind == "companion_duplicate_active"
        source["companions"].first["environment"] = value
        source["companions"] << { "command" => "other-helper", "environment" => value }
      elsif kind == "mapping_invalid"
        source["environment"] = { value => "alpha-helper" }
      elsif kind == "mapping_unknown_command"
        source["environment"] = { "ALPHA_HELPER" => value }
      else
        source["companions"].first["environment"] = value
      end
      write_manifest
      before = snapshot
      [%w[use brew alpha], ["status"], ["doctor"]].each do |args|
        output = failure(cli(*args), 1, /arcana source: .*companion|arcana source: .*environment/)
        refute_match(/from .*:\d+|Traceback|NoMethodError|TypeError/, output)
        assert_equal before, snapshot
      end
      assert_no_brew
    end
  end

  def test_state_rename_failure_rolls_back_new_owned_artifacts_and_preserves_prior_state
    success(select("dev", "beta"))
    before = snapshot.reject { |_path, entry| entry.first == "directory" }
    checkout = copy_checkout
    File.open(File.join(checkout, "scripts", "arcana-dispatch.rb"), "a") { |file| file.puts("\n# New rollback runtime.") }
    ready = File.join(@tmp, "rename-ready")
    release = File.join(@tmp, "rename-release")
    hook = <<~RUBY
      File.singleton_class.prepend(Module.new do
        def rename(from, to)
          if to == ENV.fetch("TEST_STATE")
            ArcanaTestBarrier.pause
            raise Errno::EIO, "injected state rename failure"
          end
          super
        end
      end)
    RUBY
    with_injected_cli(hook, "use", "dev", "alpha", "--dev-root", @dev,
                      script: File.join(checkout, "scripts", "arcana"),
                      env: { "TEST_STATE" => state_path, "TEST_READY" => ready, "TEST_RELEASE" => release }) do |out, err, child|
      wait_for_barrier(ready, child, err)
      assert_equal ["beta"], state["apps"].keys
      assert File.executable?(File.join(@bin, "alpha"))
      assert_equal 2, Dir.glob(File.join(File.dirname(state_path), "dispatch-v1-*.rb")).size
      File.write(release, "release")
      failure(child_result(out, err, child), 1, /injected state rename failure/)
    end
    assert_equal before, snapshot.reject { |_path, entry| entry.first == "directory" }
    success(launch("beta"))
    assert_no_brew
  end

  %w[regular symlink broken_symlink].each do |kind|
    define_method("test_#{kind}_collision_after_preflight_is_not_clobbered_or_rolled_back") do
      success(select("dev", "beta"))
      original_state = File.binread(state_path)
      collision = File.join(@bin, "alpha-extra")
      ready = File.join(@tmp, "collision-ready")
      release = File.join(@tmp, "collision-release")
      hook = <<~RUBY
        File.singleton_class.prepend(Module.new do
          def link(from, to)
            ArcanaTestBarrier.pause if to == ENV.fetch("TEST_COLLISION")
            super
          end
        end)
      RUBY
      with_injected_cli(hook, "use", "dev", "alpha", "--dev-root", @dev,
                        env: { "TEST_COLLISION" => collision, "TEST_READY" => ready, "TEST_RELEASE" => release }) do |out, err, child|
        wait_for_barrier(ready, child, err)
        if kind == "regular"
          executable(collision, "#!/bin/sh\nexit 71\n")
        else
          destination = kind == "symlink" ? target("dev", "alpha", "alpha-extra") : File.join(@tmp, "absent")
          File.symlink(destination, collision)
        end
        identity = File.lstat(collision).ino
        content = File.symlink?(collision) ? File.readlink(collision) : File.binread(collision)
        File.write(release, "release")
        failure(child_result(out, err, child), 1, /exist/i)
        assert_equal identity, File.lstat(collision).ino
        assert_equal content, File.symlink?(collision) ? File.readlink(collision) : File.binread(collision)
      end
      assert_equal original_state, File.binread(state_path)
      refute File.exist?(File.join(@bin, "alpha"))
      assert_empty Dir.glob(File.join(@bin, ".arcana-publish-*"))
      success(launch("beta"))
      assert_no_brew
    end
  end

  def test_concurrent_preflight_cannot_observe_half_written_artifact
    ready = File.join(@tmp, "partial-ready")
    release = File.join(@tmp, "partial-release")
    lock_ready = File.join(@tmp, "second-writer-lock-ready")
    hook = <<~RUBY
      require "tempfile"
      Tempfile.prepend(Module.new do
        def write(content)
          return super unless File.basename(path).start_with?(".arcana-publish-") && !@arcana_test_paused
          @arcana_test_paused = true
          midpoint = content.bytesize / 2
          written = super(content.byteslice(0, midpoint))
          flush
          ArcanaTestBarrier.pause
          written + super(content.byteslice(midpoint, content.bytesize - midpoint))
        end
      end)
    RUBY
    lock_hook = <<~RUBY
      File.prepend(Module.new do
        def flock(operation)
          File.write(ENV.fetch("TEST_LOCK_READY"), "ready") if operation == File::LOCK_EX
          super
        end
      end)
    RUBY
    with_injected_cli(hook, "use", "dev", "alpha", "--dev-root", @dev,
                      env: { "TEST_READY" => ready, "TEST_RELEASE" => release }) do |out, err, child|
      wait_for_barrier(ready, child, err)
      assert_empty Dir.glob(File.join(File.dirname(state_path), "dispatch-v1-*.rb"))
      refute File.exist?(state_path)
      with_injected_cli(lock_hook, "use", "dev", "beta", "--dev-root", @dev,
                        env: { "TEST_LOCK_READY" => lock_ready }) do |out2, err2, child2|
        wait_for_barrier(lock_ready, child2, err2)
        refute File.exist?(state_path)
        File.write(release, "release")
        success(child_result(out, err, child))
        success(child_result(out2, err2, child2))
      end
    end
    assert_equal %w[alpha beta], state["apps"].keys.sort
    success(cli("doctor"))
    success(launch("alpha"))
    success(launch("beta"))
    assert_empty Dir.glob(File.join(File.dirname(state_path), ".arcana-publish-*"))
    assert_no_brew
  end

  def test_diagnostics_are_read_only_before_and_after_selection_and_when_unhealthy
    before = snapshot
    %w[status doctor].each do |command|
      assert_match(/unselected/, success(cli(command)))
      assert_equal before, snapshot
    end
    success(select("dev", "alpha"))
    before = snapshot
    %w[status doctor].each do |command|
      output = success(cli(command))
      assert_match(/alpha: dev/, output)
      assert_match(/alpha-helper/, output)
      assert_equal before, snapshot
    end
    File.unlink(target("dev", "alpha", "alpha-helper"))
    File.unlink(File.join(@bin, "alpha-extra"))
    before = snapshot
    %w[status doctor].each do |command|
      output = failure(cli(command), 1, /alpha-helper/)
      assert_match(/missing dispatcher/, output)
      assert_equal before, snapshot
    end
    assert_no_brew
  end

  def test_concurrent_selections_keep_both_commits_and_valid_json
    ready = Queue.new
    start = Queue.new
    threads = %w[alpha beta].map do |app|
      Thread.new do
        ready << true
        start.pop
        select("dev", app)
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each { |thread| success(thread.value) }
    assert_equal %w[alpha beta], state["apps"].keys.sort
    success(launch("alpha"))
    success(launch("beta"))
    success(cli("doctor"))
    assert_empty Dir.glob(File.join(File.dirname(state_path), ".sources-*"))
    assert_no_brew
  end

  %w[linux macos].each do |platform|
    define_method("test_shipped_registry_all_on_#{platform}") do
      @data = YAML.safe_load(File.read(File.expand_path("../tools.yaml", SCRIPTS)))
      write_manifest
      supported = @data.fetch("formulae").select do |app|
        app.key?("sources") && (!app.key?("platforms") || app["platforms"].include?(platform))
      end
      supported.each do |app|
        bundle = app.fetch("sources")
        helpers = bundle.fetch("companions", []).select do |entry|
          !entry.key?("platforms") || entry["platforms"].include?(platform)
        end
        (bundle.fetch("commands") + helpers.map { |entry| entry.fetch("command") }).each do |command|
          executable(File.join(@dev, app.fetch("name"), "bin", command), "#!/bin/sh\nexit 0\n")
        end
      end
      success(cli("use", "dev", "--all", "--dev-root", @dev, env: { "ARCANA_PLATFORM" => platform }))
      assert_equal supported.map { |app| app.fetch("name") }.sort, state["apps"].keys.sort
      refute state["apps"].key?("arcana")
      refute state["apps"].key?("mind-weaver")
      helper = platform == "macos" ? "wisp-hint-macos" : "wisp-hint-linux"
      assert_equal File.join(@dev, "wisp", "bin", helper), state["apps"]["wisp"]["environment"]["WISP_HINT_HELPER"]
      assert_equal File.join(@dev, "djinn", "bin", "djinn-ui"), state["apps"]["djinn"]["environment"]["DJINN_UI_BIN"]
      success(cli("doctor", env: { "ARCANA_PLATFORM" => platform }))
      assert_no_brew
    end
  end

  def test_installed_layout_loads_packaged_modules_through_public_symlink
    prefix = File.join(@tmp, "installed prefix")
    share = File.join(prefix, "share", "arcana")
    installed_bin = File.join(prefix, "bin")
    FileUtils.mkdir_p([share, installed_bin])
    FileUtils.cp(File.join(SCRIPTS, "arcana"), File.join(installed_bin, "arcana"))
    %w[arcana-source.rb arcana-dispatch.rb].each do |name|
      FileUtils.cp(File.join(SCRIPTS, name), File.join(share, name))
    end
    FileUtils.cp(@manifest, File.join(share, "tools.yaml"))
    public_command = File.join(@path, "arcana")
    File.symlink(File.join(installed_bin, "arcana"), public_command)
    success(cli("use", "dev", "alpha", "--dev-root", @dev, script: public_command,
                env: { "ARCANA_TOOLS_YAML" => nil }))
    success(launch("alpha"))
    assert_no_brew
  end

  %w[coven numen].each do |app|
    define_method("test_#{app}_producer_receives_public_identity_not_private_target") do
      @data["formulae"] = [{ "name" => app, "sources" => { "commands" => [app] } }]
      @data.delete("optional")
      write_manifest
      key = "ARCANA_PUBLIC_#{app.upcase}"
      %w[dev brew].each do |kind|
        path = kind == "dev" ? File.join(@dev, app, "bin", app) : File.join(@brew, "opt", app, "bin", app)
        executable(path, "#!#{RbConfig.ruby} --disable=gems\nputs ENV.fetch(#{key.dump})\n")
        success(select(kind, app))
        assert_equal File.join(@bin, app), success(launch(app, env: { key => "/stale/inherited/payload" })).strip
      end
      assert_no_brew
    end
  end
end
