"""Offline Wisp packaging checks; never build or launch a native helper."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WispPackagingTests(unittest.TestCase):
    def test_platform_helpers_are_packaged_without_python_rewriting(self):
        formula = (ROOT / "Formula" / "wisp.rb").read_text()
        install = formula.split("  def install\n", 1)[1].split("  def caveats\n", 1)[0]
        self.assertIn('system "go", "build", "-o", bin/"wisp", "./cmd/wisp"', install)
        self.assertIn('if OS.mac?\n      system "swiftc", "-O", "-o", '
                      'bin/"wisp-hint-macos", "cmd/wisp-hint-macos/main.swift"', install)
        self.assertIn('else\n      bin.install "cmd/wisp-hint-linux/main.py" => "wisp-hint-linux"', install)
        self.assertIn('(bin/"wisp-hint-linux").chmod 0755', install)
        self.assertIn('zsh_completion.install', install)
        self.assertIn('bash_completion.install', install)
        for forbidden in ("rewrite_shebang", "inreplace", 'depends_on "python',
                          "service do", "launchctl", 'depends_on xcode:',
                          'system "wisp', 'system bin/', '"bindings"'):
            self.assertNotIn(forbidden, formula)

    def test_formula_tests_only_inspect_help_doctor_and_helper_executable(self):
        formula = (ROOT / "Formula" / "wisp.rb").read_text()
        test = formula.split("  test do\n", 1)[1]
        self.assertIn('shell_output("#{bin}/wisp --help")', test)
        self.assertIn('shell_output("#{bin}/wisp doctor")', test)
        self.assertEqual(test.count("shell_output("), 2)
        self.assertIn('helper = OS.mac? ? "wisp-hint-macos" : "wisp-hint-linux"', test)
        self.assertIn('assert_predicate bin/helper, :executable?', test)

    def test_caveats_and_readme_explain_passive_palette_and_optional_menu(self):
        formula = (ROOT / "Formula" / "wisp.rb").read_text()
        readme = (ROOT / "README.md").read_text()
        for text in (formula, readme):
            for expected in ("wisp palette [show|close|text]", "native passive Palette",
                             "Option+Space (Alt+Space)", "prefix mode",
                             "wisp menu", "Kitty/fzf", "~/.config/wisp/actions.toml",
                             "Installation does not modify", "launch the native helper",
                             "/usr/bin/python3", "PyGObject", "Pycairo", "GTK 3",
                             "gtk-layer-shell"):
                self.assertIn(expected, text)
            self.assertNotIn("fzf powers `wisp palette`", text)
        self.assertIn("if OS.linux?", formula)
        self.assertIn('depends_on "fzf"', formula)


if __name__ == "__main__":
    unittest.main()
