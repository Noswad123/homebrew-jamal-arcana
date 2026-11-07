require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "rbconfig"
require "shellwords"
require "tmpdir"

module DjinnPackagingSandbox
  class InstallPath < Pathname
    def install(files)
      FileUtils.mkdir_p(self)
      files.each do |source, destination|
        FileUtils.mv(source, self/destination)
      end
    end
  end

  class Formula
    class << self
      def desc(*args); end
      def homepage(*args); end
      def url(*args); end
      def version(*args); end
      def license(*args); end
      def revision(*args); end
      def depends_on(*args); end
      def test; end
    end

    attr_reader :bin, :libexec, :opt_bin, :commands

    def initialize(root)
      @bin = InstallPath.new(root/"installed bin")
      @libexec = InstallPath.new(root/"private libexec")
      @opt_bin = InstallPath.new(root/"stable opt"/"bin")
      @commands = []
    end

    def std_cargo_args(path:)
      ["--path", path]
    end

    def system(*args)
      @commands << args
      true
    end
  end

  formula_path = File.expand_path("../Formula/djinn.rb", __dir__)
  module_eval(File.read(formula_path), formula_path, 1)

  class Djinn
    def patch_djinn_ui_prompt_environment!; end
  end
end

class DjinnPackagingTest < Minitest::Test
  def setup
    @temporary_directory = Dir.mktmpdir("djinn packaging ")
    root = Pathname.new(@temporary_directory)/"prefix with spaces ' $;"
    @formula = DjinnPackagingSandbox::Djinn.new(root)
    @home = root/"separate home"
    @cwd = root/"working directory"
    [@formula.bin, @home, @cwd].each { |path| FileUtils.mkdir_p(path) }

    # The install method moves this probe to libexec before writing its wrapper.
    probe = <<~RUBY
      STDOUT.write(JSON.generate(
        "ui_bin_set" => ENV.key?("DJINN_UI_BIN"),
        "ui_bin" => ENV["DJINN_UI_BIN"],
        "args" => ARGV,
        "cwd" => Dir.pwd,
        "home" => ENV["HOME"]
      ))
      exit 37
    RUBY
    cli = @formula.bin/"djinn"
    cli.write("#!/bin/sh\nexec #{Shellwords.escape(RbConfig.ruby)} -rjson -e #{Shellwords.escape(probe)} \"$@\"\n")
    cli.chmod(0755)
    @formula.install
  end

  def teardown
    FileUtils.remove_entry(@temporary_directory) if @temporary_directory
  end

  def test_unset_ui_bin_uses_stable_opt_default
    assert_wrapper(nil, (@formula.opt_bin/"djinn-ui").to_s)
  end

  def test_explicit_ui_bin_is_preserved
    override = "/selected bundle ' $;/djinn-ui"
    assert_wrapper(override, override)
  end

  def test_explicit_empty_ui_bin_is_preserved
    assert_wrapper("", "")
  end

  private

  def assert_wrapper(ui_bin, expected)
    wrapper = @formula.bin/"djinn"
    assert_equal 0755, wrapper.stat.mode & 0777
    assert (@formula.libexec/"djinn").executable?
    assert_equal [
      ["cargo", "install", "--path", "crates/djinn-cli"],
      ["make", "install-ui", "INSTALL_DIR=#{@formula.bin}"]
    ], @formula.commands

    args = ["argument with spaces", "", "'quoted'", '$(exit 91); * & | < > "$HOME"', "line\nbreak"]
    environment = { "HOME" => @home.to_s, "DJINN_UI_BIN" => ui_bin }
    stdout, stderr, status = Open3.capture3(
      environment, wrapper.to_s, *args,
      chdir: @cwd.to_s, unsetenv_others: true
    )

    assert_equal "", stderr
    assert_equal 37, status.exitstatus
    result = JSON.parse(stdout)
    assert_equal true, result.fetch("ui_bin_set")
    assert_equal expected, result.fetch("ui_bin")
    assert_equal args, result.fetch("args")
    assert_equal @cwd.realpath.to_s, result.fetch("cwd")
    assert_equal @home.to_s, result.fetch("home")
  end
end
