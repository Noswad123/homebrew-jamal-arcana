"""Offline packaging regressions; never build, install, or run the release CLI."""

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
FORMULA = ROOT / "Formula" / "mw.rb"
PIN = "4745d03ac750c45ae52f63b736620fdc617b0541"
CHECKSUM = "8290c19c9845e0d1c3020c188fb93b53b4b06217658bbf5682c7b41dd32053bd"

loader = importlib.machinery.SourceFileLoader("arcana_release_test", str(ROOT / "scripts" / "release"))
spec = importlib.util.spec_from_loader(loader.name, loader)
release = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = release  # dataclasses resolves annotations through sys.modules.
loader.exec_module(release)


class MwPackagingTests(unittest.TestCase):
    def test_pinned_rust_formula(self):
        text = FORMULA.read_text()
        self.assertIn(f'url "https://github.com/Noswad123/mind-weaver/archive/{PIN}.tar.gz"', text)
        self.assertIn(f'sha256 "{CHECKSUM}"', text)
        self.assertRegex(text, r'(?m)^  version "0\.1\.3"$')
        self.assertRegex(text, r'(?m)^  revision 1$')
        self.assertRegex(text, r'depends_on "rust"\s*=>\s*:build')
        self.assertRegex(text, r'system "cargo", "install", \*std_cargo_args\(path:\s*["\x27]crates/mw["\x27]\)')
        self.assertNotRegex(text, r'depends_on "go"|system "go"|std_go_args|ldflags')

    def test_release_rewrite_resets_packaging_revision(self):
        original = FORMULA.read_text()
        self.assertEqual(release.formula_version(original, None), "0.1.3")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mw.rb"
            path.write_text(original)
            formula = release.load_formula(path, Path(directory))
            self.assertEqual(formula.current_version, "0.1.3")
            self.assertEqual(formula.repo_slug, "Noswad123/mind-weaver")
            self.assertEqual(release.bump_version(formula.current_version, "patch"), "0.1.4")
            with mock.patch.object(release, "run", side_effect=AssertionError("external command")):
                with contextlib.redirect_stdout(io.StringIO()):
                    release.update_formula_file(formula, "v0.1.4", "a" * 64, dry_run=False)
            rewritten = path.read_text()
            self.assertEqual(release.formula_version(rewritten, None), "0.1.4")
            self.assertNotRegex(rewritten, r"(?m)^\s*(version|revision)\s+")
            expected = []
            for line in original.splitlines():
                if line.strip().startswith(("version ", "revision ")):
                    continue
                if line.strip().startswith("url "):
                    line = '  url "https://github.com/Noswad123/mind-weaver/archive/refs/tags/v0.1.4.tar.gz"'
                elif line.strip().startswith("sha256 "):
                    line = f'  sha256 "{"a" * 64}"'
                expected.append(line)
            # Exact comparison also preserves the Rust build, test block, and head.
            self.assertEqual(rewritten, "\n".join(expected) + "\n")

    def test_migration_caveats_disclose_compatibility_limits(self):
        formula = FORMULA.read_text()
        readme = (ROOT / "README.md").read_text()
        self.assertIn("def caveats", formula)
        self.assertNotIn('desc "Local-first notes, todos, and optional Hive Mind sync CLI"', formula)
        for text in (formula, readme):
            self.assertIn("migration preview", text)
            self.assertIn("Hive Sync", text)
            self.assertIn("mw sync", text)
            self.assertIn("mw todos snapshot --json", text)
            self.assertIn("task-safety-v1", text)

    def test_release_rewrite_dry_run_preserves_bytes(self):
        original = FORMULA.read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mw.rb"
            path.write_bytes(original)
            formula = release.load_formula(path, Path(directory))
            with mock.patch.object(release, "run", side_effect=AssertionError("external command")):
                with contextlib.redirect_stdout(io.StringIO()):
                    release.update_formula_file(formula, "v0.1.4", "a" * 64, dry_run=True)
            self.assertEqual(path.read_bytes(), original)

    def test_arcana_only_upgrades_outdated_mw(self):
        ruby = shutil.which("ruby")
        if ruby is None:
            self.skipTest("Ruby is required for the Arcana regression harness")
        harness = r'''
require "json"
def system(*)
  raise "unexpected external command"
end
ARGV.replace(["list", "--no-casks"])
path = ENV.fetch("ARCANA_TEST_SCRIPT")
# Skip only the polyglot shell launcher, not any Ruby definitions or dispatch.
eval(File.read(path).split("#!ruby\n", 2).fetch(1), TOPLEVEL_BINDING, path)
def brew_available?; false; end
def capture(*); raise "unexpected external command"; end
def outdated_names(kind)
  raise "unexpected package kind" unless kind == "--formula"
  @outdated
end
def formula_installed?(name); name == "mw"; end
def run(*args, **)
  @commands << args
end
data = manifest
options = Options.new(dry_run: false, include_optional: false, include_casks: false)
item = formula_items(data, options).find { |entry| item_name(entry) == "mw" }
raise "mw must not refresh on every update" if reinstall_on_update?(item)
installed = Set["mw"]
@outdated = Set.new
current = formula_update_target_names(data, options, installed)
@commands = []
upgrade_formulae(data, options, only_names: current)
current_commands = @commands.dup
@outdated = Set["mw"]
outdated = formula_update_target_names(data, options, installed)
missing = formula_update_target_names(data, options, Set.new)
@commands = []
upgrade_formulae(data, options, only_names: outdated)
puts "ARCANA_TEST_RESULT=" + JSON.generate({
  current: current.to_a, current_commands: current_commands,
  outdated: outdated.to_a, missing: missing.to_a, commands: @commands
})
'''
        env = dict(os.environ, ARCANA_PLATFORM="linux",
                   ARCANA_TOOLS_YAML=str(ROOT / "tools.yaml"),
                   ARCANA_TEST_SCRIPT=str(ROOT / "scripts" / "arcana"),
                   PATH="")
        result = subprocess.run([ruby, "--disable=gems", "-e", harness],
                                env=env, capture_output=True, text=True, check=True)
        marker = "ARCANA_TEST_RESULT="
        payload = next(line.removeprefix(marker) for line in result.stdout.splitlines()
                       if line.startswith(marker))
        self.assertEqual(json.loads(payload), {
            "current": [], "current_commands": [], "outdated": ["mw"],
            "missing": [], "commands": [["brew", "upgrade", "Noswad123/jamal-arcana/mw"]],
        })


if __name__ == "__main__":
    unittest.main()
