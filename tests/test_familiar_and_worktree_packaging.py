"""Offline packaging checks: no builds, installs, upstream edits, or release CLI."""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
NAMES = ("numen", "yggdrasil")

loader = importlib.machinery.SourceFileLoader(
    "arcana_additions_release_test", str(ROOT / "scripts" / "release")
)
spec = importlib.util.spec_from_loader(loader.name, loader)
release = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = release
loader.exec_module(release)


class FamiliarAndWorktreePackagingTests(unittest.TestCase):
    def test_yggdrasil_installs_ygg_with_git_dependency(self):
        text = (ROOT / "Formula" / "yggdrasil.rb").read_text()
        self.assertIn('depends_on "go" => :build', text)
        self.assertIn('depends_on "git"', text)
        self.assertIn('std_go_args(output: bin/"ygg"), "./cmd/ygg"', text)
        self.assertIn('shell_output("#{bin}/ygg help")', text)
        self.assertIn('shell_output("#{bin}/ygg hooks help")', text)

    def test_numen_builds_embedded_assets_and_tests_without_gui(self):
        text = (ROOT / "Formula" / "numen.rb").read_text()
        self.assertIn('depends_on :macos', text)
        self.assertIn('depends_on "rust" => :build', text)
        self.assertIn('system "cargo", "install", *std_cargo_args', text)
        test_block = text.split("  test do\n", 1)[1]
        self.assertIn('shell_output("#{bin}/numen check-assets")', test_block)
        self.assertIn('"validated embedded RGBA atlas"', test_block)
        self.assertNotIn('/numen run', test_block)
        self.assertNotIn('SDKROOT', text)
        self.assertNotIn('service do', text)

    def test_numen_launch_guidance_distinguishes_runtime_from_installation(self):
        formula = (ROOT / "Formula" / "numen.rb").read_text()
        readme = (ROOT / "README.md").read_text()
        self.assertIn('version "0.1.0-dev"', formula)
        self.assertIn('branch: "main"', formula)
        self.assertIn("Open one unattached familiar with:\n        numen\n", formula)
        self.assertIn("reuses the graphical runtime service", formula)
        self.assertIn("bootstraps it detached", formula)
        self.assertIn("foreground alternative", formula)
        self.assertIn("Installation does not launch Numen", formula)
        self.assertIn("register OS services/autostart", formula)
        self.assertIn("numen check-assets # headless", readme)
        self.assertIn("numen              # open one unattached familiar", readme)
        self.assertIn("numen run          # foreground alternative", readme)
        self.assertNotIn("9937f9f", readme)
        self.assertNotIn("Those require subsequent upstream changes", readme)
        self.assertIn("reinstall_on_update: true", readme)
        self.assertIn("redistribution permissions", readme)
        self.assertIn("does not publish upstream changes", readme)

    def test_release_helper_can_read_and_rewrite_both_formulae(self):
        for name in NAMES:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / f"{name}.rb"
                original = (ROOT / "Formula" / path.name).read_text()
                self.assertIn(
                    f'url "https://github.com/Noswad123/{name}.git", branch: "main"',
                    original,
                )
                path.write_text(original)
                formula = release.load_formula(path, Path(directory))
                self.assertEqual(formula.repo_slug, f"Noswad123/{name}")
                # The release helper strips the development suffix for bumping.
                self.assertEqual(formula.current_version, "0.1.0")
                with mock.patch.object(release, "run", side_effect=AssertionError("external command")):
                    with contextlib.redirect_stdout(io.StringIO()):
                        release.update_formula_file(formula, "v0.1.1", "a" * 64, dry_run=False)
                rewritten = path.read_text()
                self.assertIn(f'/archive/refs/tags/v0.1.1.tar.gz"', rewritten)
                self.assertEqual(
                    original.split("  def install\n", 1)[1],
                    rewritten.split("  def install\n", 1)[1],
                )

    def test_manifest_commands_platforms_and_refresh_selection(self):
        ruby = shutil.which("ruby")
        if ruby is None:
            self.skipTest("Ruby required for Arcana manifest evaluation")
        harness = r'''
require "json"
require "rbconfig" # Apple's system Ruby needs uname while loading this library.
ENV["PATH"] = ""
def system(*); raise "unexpected external command"; end
ARGV.replace(["list", "--no-casks"])
path = ENV.fetch("ARCANA_TEST_SCRIPT")
eval(File.read(path).split("#!ruby\n", 2).fetch(1), TOPLEVEL_BINDING, path)
def outdated_names(*); Set.new; end
data = manifest
options = Options.new(dry_run: false, include_optional: false, include_casks: false)
entries = formula_items(data, options)
all_names = required_formulae(data).map { |item| item_name(item) }
expected = Dir[File.join(File.dirname(path), "..", "Formula", "*.rb")].map { |p| File.basename(p, ".rb") }
raise "manifest/formula mismatch" unless all_names.sort == expected.sort
puts "ARCANA_TEST_RESULT=" + JSON.generate({
  commands: entries.select { |item| %w[numen yggdrasil].include?(item_name(item)) }
                   .to_h { |item| [item_name(item), item.fetch("command")] },
  targets: formula_update_target_names(data, options, Set["numen", "yggdrasil"]).to_a
})
'''
        for platform, expected in (("macos", {"numen": "numen", "yggdrasil": "ygg"}),
                                   ("linux", {"yggdrasil": "ygg"})):
            with self.subTest(platform=platform):
                env = dict(os.environ, ARCANA_PLATFORM=platform,
                           ARCANA_TOOLS_YAML=str(ROOT / "tools.yaml"),
                           ARCANA_TEST_SCRIPT=str(ROOT / "scripts" / "arcana"))
                result = subprocess.run([ruby, "--disable=gems", "-e", harness], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                marker = "ARCANA_TEST_RESULT="
                payload = next(line.removeprefix(marker) for line in result.stdout.splitlines()
                               if line.startswith(marker))
                self.assertEqual(json.loads(payload), {
                    "commands": expected, "targets": list(expected),
                })


if __name__ == "__main__":
    unittest.main()
