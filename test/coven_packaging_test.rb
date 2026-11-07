require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "shellwords"
require "tmpdir"

module CovenPackagingSandbox
  class InstallPath < Pathname
    def install(*files)
      FileUtils.mkdir_p(self)
      files.each { |file| FileUtils.mv(file, self) }
    end
  end

  class Formula
    class << self
      attr_accessor :python_opt_bin

      def desc(*args); end
      def homepage(*args); end
      def url(*args); end
      def version(*args); end
      def license(*args); end
      def revision(*args); end
      def depends_on(*args); end
      def test; end

      def [](name)
        raise "unexpected dependency #{name}" unless name == "python@3.13"

        Struct.new(:opt_bin).new(python_opt_bin)
      end
    end

    attr_reader :bin, :libexec, :opt_bin, :opt_libexec

    def initialize(root)
      @bin = InstallPath.new(root/"installed bin")
      @libexec = InstallPath.new(root/"private libexec")
      @opt_bin = root/"stable opt"/"bin"
      @opt_libexec = root/"stable opt"/"libexec"
    end
  end

  formula_path = File.expand_path("../Formula/coven.rb", __dir__)
  module_eval(File.read(formula_path), formula_path, 1)
end

class CovenPackagingTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("coven packaging ")
    root = Pathname.new(@tmp)/"prefix with spaces ' $;"
    @formula = CovenPackagingSandbox::Coven.new(root)
    @home = root/"separate home"
    @cwd = root/"working directory"
    @misleading_path = root/"misleading path"
    python_bin = root/"python stable opt"/"bin"
    [@formula.bin, @formula.opt_libexec.dirname, @home, @cwd, @misleading_path, python_bin].each do |path|
      FileUtils.mkdir_p(path)
    end
    CovenPackagingSandbox::Formula.python_opt_bin = python_bin
    probe = <<~RUBY
      STDOUT.write(JSON.generate(
        "args" => ARGV, "coven_home" => ENV["COVEN_HOME"],
        "command" => ENV["COVEN_COMMAND"], "home" => ENV["HOME"], "cwd" => Dir.pwd
      ))
      STDERR.write("declared python probe\n")
      exit 37
    RUBY
    python = python_bin/"python3.13"
    python.write("#!/bin/sh\nexec #{Shellwords.escape(RbConfig.ruby)} --disable=gems -rjson -e #{Shellwords.escape(probe)} \"$@\"\n")
    python.chmod(0755)
    %w[python3 python3.13].each do |name|
      trap = @misleading_path/name
      trap.write("#!/bin/sh\nexit 97\n")
      trap.chmod(0755)
    end
    source = root/"source"
    %w[bin runner examples].each { |name| FileUtils.mkdir_p(source/name) }
    (source/"runner/coven.py").write("runner sentinel\n")
    %w[README.md LICENSE].each { |name| (source/name).write(name) }
    Dir.chdir(source) { @formula.install }
    File.symlink(@formula.libexec, @formula.opt_libexec)
  end

  def teardown
    FileUtils.remove_entry(@tmp) if @tmp
  end

  def test_resources_and_executable_wrapper_are_installed
    assert_equal 0755, (@formula.bin/"coven").stat.mode & 0777
    %w[bin runner examples README.md LICENSE].each do |name|
      assert (@formula.libexec/name).exist?, name
    end
  end

  def test_callback_precedence_and_empty_values_with_misleading_python_path
    public_path = "/public launcher ' $;/coven"
    explicit = "/explicit callback ' $;/coven"
    [[nil, nil, @formula.opt_bin/"coven"], [nil, public_path, public_path],
     [explicit, public_path, explicit], ["", public_path, public_path],
     [nil, "", @formula.opt_bin/"coven"], ["", "", @formula.opt_bin/"coven"],
     ["", nil, @formula.opt_bin/"coven"], [explicit, "", explicit]].each do |command, public, expected|
      assert_wrapper({ "COVEN_COMMAND" => command, "ARCANA_PUBLIC_COVEN" => public },
                     @formula.opt_libexec, expected, @misleading_path.to_s)
    end
  end

  def test_home_hints_and_empty_home_with_minimal_system_path
    [nil, "", "/custom home ' $;"].each do |home|
      expected = home.nil? || home.empty? ? @formula.opt_libexec : home
      assert_wrapper({ "COVEN_HOME" => home }, expected, @formula.opt_bin/"coven", "/usr/bin:/bin")
    end
  end

  private

  def assert_wrapper(overrides, expected_home, expected_command, path)
    args = ["argument with spaces", "", "'quoted'", '$(exit 91); * & | < > "$HOME"', "line\nbreak"]
    environment = { "HOME" => @home.to_s, "PATH" => path }.merge(overrides)
    out, err, status = Open3.capture3(environment, (@formula.bin/"coven").to_s, *args,
                                     chdir: @cwd.to_s, unsetenv_others: true)
    assert_equal 37, status.exitstatus
    assert_equal "declared python probe\n", err
    result = JSON.parse(out)
    assert_equal ["#{expected_home}/runner/coven.py", *args], result.fetch("args")
    assert_equal expected_home.to_s, result.fetch("coven_home")
    assert_equal expected_command.to_s, result.fetch("command")
    assert_equal @home.to_s, result.fetch("home")
    assert_equal @cwd.realpath.to_s, result.fetch("cwd")
  end
end
