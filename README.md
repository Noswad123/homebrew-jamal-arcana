# Homebrew Jamal Arcana

Homebrew tap for Jamal Arcana tools.

This tap supports macOS Homebrew and personal Linuxbrew installs. On Linux,
`arcana` installs formulae and automatically skips macOS-only casks.

## Install

Install or update the whole tap-managed ecosystem from this repo's manifest:

```bash
brew install Noswad123/jamal-arcana/arcana
arcana install
arcana update
```

On Linux, install Homebrew/Linuxbrew first, then run the same commands. Numen,
the native MindWeaver app cask, and optional GUI casks are macOS-only and are
skipped automatically; use `--no-casks` to explicitly exclude casks in dry runs
or scripts.

### Bootstrap a Linux machine

Install Linuxbrew/Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Load Homebrew into the current shell and add the same line to your shell startup
file, such as `~/.zshrc` or `~/.bashrc`:

```bash
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
```

For a no-sudo, user-local install, use `~/.linuxbrew` instead:

```bash
mkdir -p "$HOME/.linuxbrew" "$HOME/.linuxbrew/bin"
git clone https://github.com/Homebrew/brew "$HOME/.linuxbrew/Homebrew"
ln -sf ../Homebrew/bin/brew "$HOME/.linuxbrew/bin/brew"
eval "$($HOME/.linuxbrew/bin/brew shellenv)"
```

Then install Arcana and the managed CLI tools:

```bash
brew install Noswad123/jamal-arcana/arcana
arcana install
```

Check the install and update later:

```bash
arcana doctor
arcana update
```

Preview the Linux plan without changing anything:

```bash
arcana install --dry-run
arcana update --dry-run
```

`arcana update` also refreshes `arcana` itself. Because the currently running
process keeps using the code it started with, run `arcana` again after an update
to use newly installed Arcana behavior immediately.

Preview changes before running them:

```bash
arcana update --dry-run
```

Refresh only the global Arcana command:

```bash
arcana self-update
```

Check that `tools.yaml`, `Formula/`, and `Casks/` are in sync:

```bash
arcana doctor
```

`doctor` also reports whether managed formulae/casks are missing, stale, or
marked for refresh on each `arcana update`.

Or install tools individually:

```bash
brew tap Noswad123/jamal-arcana
brew install arcana
brew install coven
brew install djinn
brew install kitsune
brew install mw
brew install numen # macOS only
brew install wisp
brew install waystone
brew install yggdrasil # provides the ygg command
brew install --cask mind-weaver
```

Or install directly:

```bash
brew install Noswad123/jamal-arcana/arcana
brew install Noswad123/jamal-arcana/coven
brew install Noswad123/jamal-arcana/djinn
brew install Noswad123/jamal-arcana/kitsune
brew install Noswad123/jamal-arcana/mw
brew install Noswad123/jamal-arcana/numen # macOS only
brew install Noswad123/jamal-arcana/wisp
brew install Noswad123/jamal-arcana/waystone
brew install Noswad123/jamal-arcana/yggdrasil # provides the ygg command
brew install --cask Noswad123/jamal-arcana/mind-weaver
```

## Formulae

- `arcana` — install and update the Jamal Arcana Homebrew ecosystem
- `coven` — create and operate magic-themed multi-agent workspaces backed by kitsune
- `djinn` — local-first companion for OpenCode and other AI coding agents
- `kitsune` — composable multiplexer kits for named working sessions
- `mw` — local-first notes and todos CLI
- `numen` — event-driven desktop familiar (macOS only; launched manually)
- `wisp` — native passive Palette and floating terminal utility surfaces
- `waystone` — save, fuzzy-pick, copy, and open frequently used paths
- `yggdrasil` — share private files across Git worktrees with local history; command: `ygg`

## Casks

- `mind-weaver` — native macOS app shell for MindWeaver

Casks are macOS-only. Linuxbrew installs platform-supported formulae from this
manifest; Numen is initially macOS-only while its Linux desktop support remains
unvalidated.

## Yggdrasil and Numen previews

Both formulae currently track upstream `main` with the tap's `0.1.0-dev` package
baseline and `reinstall_on_update: true`. There is no tagged release implied by
that version. They build published source, not uncommitted sibling checkouts.
The installed feature set depends on the source published to upstream `main`;
editing this tap or a sibling checkout does not publish upstream changes.
Neither upstream currently declares a project license; these formulae do not
invent one. Resolve code/artwork redistribution permissions before publishing
bottles or redistributing artifacts.

Yggdrasil builds with Go and installs **`ygg`**, with Git as a runtime dependency.
Installation does not initialize private stores or install Git hooks:

```bash
ygg help
ygg hooks help
```

Numen builds with Rust and embeds its artwork in the executable. Installation
does not launch Numen, register an OS service, or enable autostart. This is
distinct from the graphical runtime service used after an explicit launch:

```bash
numen check-assets # headless validation of the embedded artwork
numen              # open one unattached familiar; reuse or bootstrap detached service
numen run          # foreground alternative in a graphical macOS session
```

## Wisp native Palette

Wisp packages `wisp-hint-macos` on macOS, built with `swiftc` and the Cocoa SDK
from Apple Command Line Tools; full Xcode is not required. Linux installs the
executable `wisp-hint-linux` script unchanged, using system `/usr/bin/python3`.
The Linux native Wayland helper additionally needs distro-provided PyGObject,
Pycairo, GTK 3 and gtk-layer-shell, not packages for Homebrew Python.

`wisp palette [show|close|text]` controls the native passive Palette. The window
manager/compositor owns Option+Space (Alt+Space) bindings and prefix mode;
showing Palette alone does not capture keys or enter mode. `wisp menu` is the
explicit optional Kitty/fzf terminal interface. Both share the action catalog
at `~/.config/wisp/actions.toml`; native Palette does not need Kitty or fzf.

Installation does not modify the action catalog or window manager configuration,
generate/load bindings, register autostart, or launch the native helper.

## Select dev or Homebrew executables

Arcana can select the executable source independently of installation and updates:

```bash
arcana source use dev numen
arcana source use brew numen wisp coven
arcana source use brew --all --dry-run
arcana source use brew --all
arcana source use dev --all
arcana source status
arcana source doctor
```

These commands require the source-selection version of Arcana. While developing
this checkout, use `./scripts/arcana source ...`; editing the checkout does not
update an already-installed Arcana or publish a new Homebrew package.

### Selection contract

- Supply one or more app IDs, **or** `--all`, never both. Omitting both is an
  error. `ygg` is also accepted as an alias for app ID `yggdrasil`.
- `--all` expands to every platform-supported formula with a `sources` bundle
  in `tools.yaml`, not just installed apps. Initially these are Coven, Djinn,
  Kitsune, mw, Numen (macOS), Waystone, Wisp, Wyrm, and Yggdrasil. Arcana itself,
  native `.app` casks, and optional third-party dependencies are not switched.
- All requested commands, required helpers, and launcher conflicts are checked
  before publication. A missing payload fails the **whole selection**; nothing
  is silently skipped or switched to another source.
- The complete selection is committed through one locked, atomic state-file
  replacement, preserving apps not named in the command. `--all` records the
  current set; it does not establish a default for future registry additions.
- `--dry-run` performs the same preflight without writing state, locks, runtimes,
  or launchers. It can still query `brew --prefix` for a brew selection.
- Selection never installs, builds, updates, launches, or restarts an app. It
  affects **new invocations only**. Existing services and workspaces keep their
  current builds and endpoints until explicitly restarted or handed off.

`status` and `doctor` are read-only and never invoke Homebrew or application
executables. They show selections, targets, required helpers, and launcher/runtime
health; they exit nonzero for unhealthy selections. Unselected apps are
informational. These checks establish file-level readiness, not protocol or
running-service compatibility.

### Stable launchers and payload locations

On successful selection, Arcana provisions permanent command launchers under
`~/.local/bin`. They read explicit selection state and execute the selected target
directly, preserving arguments, working directory, environment, stdio, exit
status, and normal `exec` signal behavior. They do not search PATH, run `brew`,
or fall back when a target disappears. Runtime code is copied into user-owned
state, so removing the source checkout or upgrading Arcana does not remove it.
Arcana's launchers use an absolute Ruby interpreter; Homebrew Ruby uses its
stable `opt` path when available rather than a version-pinned Cellar path.

Payload layout:

```text
public entrypoint: ~/.local/bin/<command>
dev payload:       ~/.local/libexec/arcana-dev/<app>/bin/<command>
brew payload:      <brew-prefix>/opt/<installed-formula>/bin/<command>
selection state:   ${XDG_STATE_HOME:-~/.local/state}/arcana/sources.json
```

The dev app directory uses the app ID, e.g. `yggdrasil/bin/ygg`. Djinn's `djinn`
and `djinn-ui` commands switch as one bundle. Wisp's platform-specific native
helper is validated with Wisp. `DJINN_UI_BIN` and `WISP_HINT_HELPER` bind companion
launches to the selected payload unless the caller explicitly supplied those
variables (an explicitly empty value also counts as an override).

Override roots when selecting an already-installed payload:

```bash
arcana source use dev numen wisp --dev-root /absolute/path/to/dev-payloads
arcana source use brew --all --brew-prefix /opt/homebrew
```

Without `--brew-prefix`, only the management command queries `brew --prefix`;
the resolved prefix is saved in the selection. Brew targets use formula `opt`
paths and remain valid across Cellar version changes. `--dev-root` is the parent
of per-app directories, not a checkout or an individual app's `bin` directory.
Root overrides apply to the current selection, not to later `use` commands.
`ARCANA_BIN_DIR` can override the public launcher directory with an absolute path;
use it consistently, since changing it does not remove old launchers.

### Existing installations and migration boundaries

**Existing files and symlinks are never overwritten**, including broken symlinks.
Only exact Arcana-owned launchers can be reused. There is deliberately no
`--force`: preview the operation, preserve existing files, and resolve conflicts
explicitly before retrying. Invalid or unsupported state is also refused rather
than replaced.

Before adopting a dev app, redirect its installer to the separate payload
directory and preserve all required companion files. For example, from the
appropriate source checkout:

```bash
# Numen: cargo install places the executable in <root>/bin.
cargo install --path . --locked --root "$HOME/.local/libexec/arcana-dev/numen"

# Wisp: install its executable and matching platform helper together.
make install INSTALL_DIR="$HOME/.local/libexec/arcana-dev/wisp/bin"

# Djinn: install both the CLI and UI.
make install INSTALL_DIR="$HOME/.local/libexec/arcana-dev/djinn/bin"
```

Existing upstream installers may still default to `~/.local/bin`. Do not run
those defaults after adopting Arcana launchers: they could replace the launcher.
Installer-default migrations and automated adoption are not part of this first
increment. Resource-bearing apps such as Coven also need their full resource
layout; merely symlinking its script into a payload `bin` is not sufficient.

Shell PATH must put the managed launcher directory ahead of Cargo/Homebrew and
other payload directories. GUI shortcuts should invoke the absolute public
launcher path. Directly invoking a checkout, `opt`, or Cellar executable bypasses
selection intentionally.

Existing generated configs are **not rewritten**. In particular, Numen's Wisp
action can still contain the executable captured when it was generated, and
Coven callbacks can contain implementation-specific paths. Migrate durable
actions to the public launcher after checking their arguments and socket intent.
Producer-side fixes are a separate follow-up; internal same-build spawning and
session-bound binary/socket references must retain their affinity.

Selection publication is atomic, but initial launcher provisioning spans multiple
directories and is not a filesystem-wide transaction. Ordinary publication errors
preserve the prior selection and remove newly created owned files; directories
and the lock may remain. A process crash can leave unselected launchers or copied
runtimes; inspect with `source doctor` and retry after resolving any conflict.

To stop using selection without deleting anything, invoke the desired payload
directly. Restoring the previous launcher files is a manual migration; no removal
or automatic daemon management is performed.

Run the isolated source-selection regressions without installing or launching
real tools:

```bash
ruby test/arcana_source_test.rb
```

## Update behavior

Some formulae currently track the `main` branch until their first tagged
releases. `arcana update` reinstalls only those tools marked
`reinstall_on_update: true`, upgrades Homebrew-outdated formulae/casks, and
installs missing manifest entries. Other installed tools are left alone.

During the package phase, `arcana update` continues with independent tools even
if one fails, then prints a summary listing every failed package and stage. It
exits with status 1 if any package step failed, or 0 otherwise. Homebrew setup
and Arcana's own refresh/restart remain fail-fast, as do `arcana install` and
`arcana self-update`. Dry runs report planned steps, not completed successes.

Forced refreshes retain the existing `uninstall --ignore-dependencies` followed
by `install` policy. This is not atomic: if installation fails after removal,
the previous installation is gone, and the summary explicitly reports that.
If removal fails, that package's install is skipped. Failed installs are not
explicitly retried by Arcana later in the same update. Homebrew still resolves
dependencies when Arcana attempts another package.

Run the isolated Ruby standard-library tests (fake Homebrew only):

```bash
ruby test/arcana_test.rb
```

### MindWeaver Rust CLI packaging

`mw` now builds the Rust CLI from workspace package `crates/mw` with Homebrew's
locked Cargo arguments. The default source is the immutable upstream commit
`4745d03ac750c45ae52f63b736620fdc617b0541`, verified by its archive SHA256, rather
than mutable `main` or the old Go `v0.1.3` source. The source requires Rust 1.89+
and bundles SQLite; the formula supplies Rust as a build dependency.

The Homebrew package is **`0.1.3_1`**: `0.1.3` preserves the previous package
baseline, while `revision 1` makes Homebrew recognize the Rust migration as an
upgrade. This does **not** claim an upstream Rust `v0.1.3` release. The pinned
Rust crate currently reports **`mw 0.1.0`**, independently of Homebrew's package
version. Its help identifies it as the Rust port.

`mw` intentionally does not use `reinstall_on_update`: rebuilding an immutable
snapshot every time would not fetch newer code. Once these tap changes are
published and pulled by `brew update`, ordinary `arcana update` selects the
outdated package and runs `brew upgrade Noswad123/jamal-arcana/mw`. A source
commit/checksum change at the same package baseline must also increment
`revision`. A later upstream release should use its real tag/version and reset
the packaging revision; the release helper now removes the old revision when
rewriting a formula for a new tag. `--HEAD` is an explicit, moving-source option,
not the default update policy.

**This is a Rust migration preview, not complete Go CLI parity.** The old Go
package provides Hive Sync (`mw sync`), including remote push/pull, diagnostics,
conflicts, and token management. This pinned Rust source does not implement that
command. Do not upgrade a workflow that depends on Hive Sync until an explicit
migration/support decision has been made; package caveats warn about the removal.
`mw seal`/`mw notes sync` only run the local notes pipeline and are not remote-sync
replacements. No silent fallback to the old Go binary is provided. Review other
existing automation against the Rust CLI help before opting into this preview.

**API compatibility is separate from installation.** This commit supports
`mw config json` and schema JSON discovery, but it does **not** implement
`mw todos snapshot --json` or the task-safety-v1 mutation protocol expected by
the newest editor/Waybar integrations. A function named `todos_snapshot_command`
only prints terminal progress bars; it is not that JSON endpoint. The package
test verifies the APIs actually present without claiming full integration
compatibility. Those integrations must remain unavailable/fail closed until the
corresponding upstream engine changes are available. Do not substitute a
DB-initializing query or automatic sync as a workaround. Installing the CLI also
does not copy or initialize your notes.

Validate this checkout without installing tools or publishing releases:

```bash
python3 -B -m unittest discover -s tests -p 'test_*.py'
ruby -c Formula/mw.rb
ruby -x -c scripts/arcana
```

The regression suite checks the source pin, Rust build, outdated-only update
selection, and revision reset for future releases using mocks and temporary
files. Do not run `scripts/release` to apply this migration: its normal workflow
creates/pushes upstream tags and commits/pushes tap changes. A newly cloned tap
checkout is also separate from Homebrew's installed tap; editing it alone does
not replace the installed `mw` binary or change what `arcana update` currently
sees.

## MindWeaver native app dependency strategy

The native MindWeaver macOS app is a SwiftUI shell around the `mw` engine.
Homebrew should provide the required CLI dependency instead of the
app bundling its own copy:

```bash
brew install Noswad123/jamal-arcana/mw
```

Optional external-editing helpers can improve the raw Markdown workflow, but the
app must continue to work without them:

```bash
brew install Noswad123/jamal-arcana/wisp
brew install neovim
brew install --cask kitty
brew install --cask nikitabobko/tap/aerospace
```

Expected fallback order in the app:

1. `wisp nvim <file>` when `wisp`, `nvim`, `kitty`, and `aerospace` are all available.
2. `kitty --detach nvim <file>` when `kitty` and `nvim` are available.
3. Terminal.app running `nvim <file>` when only `nvim` is available.
4. GUI `$VISUAL`/`$EDITOR` commands such as `code`, `cursor`, `subl`, `mate`, `bbedit`, or `zed`.
5. TextEdit via `open -e <file>` as the safe default.

The native app cask declares `mw` as its required formula dependency and leaves
`wisp`, `neovim`, `kitty`, and `aerospace` as documented optional enhancements.
The CLI formula's migration to Rust is not proof of Swift app protocol parity;
test the app's workflows separately on macOS before relying on the new engine.

The cask expects a release ZIP named with this convention:

```text
MindWeaver-<version>.zip
```

uploaded to the Swift app repository release:

```text
https://github.com/Noswad123/mind-weaver-swift/releases/tag/v<version>
```

For example:

```text
https://github.com/Noswad123/mind-weaver-swift/releases/download/v0.1.0/MindWeaver-0.1.0.zip
```

The release helper computes the ZIP checksum and updates `Casks/mind-weaver.rb`.

## Release formulae and casks

Use the release helper from this tap repo. It defaults to executing a patch
bump for every formula:

```bash
scripts/release
```

Preview the workflow without changing anything:

```bash
scripts/release --dry-run
```

Control the version part with `-p`:

```bash
scripts/release -p minor
scripts/release -p major
```

Release only one tool:

```bash
scripts/release -t wisp
```

`-t` is an alias for `--tool`, and may be repeated or comma-separated.

### Normal MindWeaver app cask release

For future MindWeaver app releases, the expected flow is:

1. Archive/export `MindWeaver.app` from Xcode.
2. Run the cask release helper with the new version.
3. Let the helper validate the app bundle shape, zip the app, create/update the GitHub release artifact, compute
   SHA256, update the cask, commit/push the tap, and sync the local Homebrew tap.

MindWeaver preview releases are not Developer ID signed or notarized. Users may
need to bypass Gatekeeper after installing:

```bash
xattr -dr com.apple.quarantine /Applications/MindWeaver.app
```

This tradeoff avoids requiring Apple Developer Program membership for now.

Use the exported app bundle directly:

```bash
scripts/release \
  --mind-weaver-app ~/Projects/mind-weaver-swift/Archive/latest/MindWeaver.app \
  --mind-weaver-version 0.1.1 \
  --upload-mind-weaver-app \
  --create-mind-weaver-release
```

If the input is a `.app` bundle, the helper creates the release ZIP:

```text
dist/MindWeaver-<version>.zip
```

using `ditto -c -k --keepParent`, computes its SHA256, and updates
`Casks/mind-weaver.rb`. If the input is already a ZIP, it computes the checksum
directly.

Before updating/uploading the cask artifact, the helper verifies that the ZIP or
input bundle contains `MindWeaver.app` and `Contents/MacOS/MindWeaver`. It does
not require Developer ID signing or Apple notarization.

To preview without mutating GitHub, the tap, or the cask:

```bash
scripts/release --dry-run \
  --mind-weaver-app ~/Projects/mind-weaver-swift/Archive/latest/MindWeaver.app \
  --mind-weaver-version 0.1.1 \
  --upload-mind-weaver-app \
  --create-mind-weaver-release
```

To update the cask locally without uploading/committing, useful for testing:

```bash
scripts/release \
  --mind-weaver-app ~/Projects/mind-weaver-swift/Archive/latest/MindWeaver.app \
  --mind-weaver-version 0.1.1 \
  --no-tap-commit
```

To use an already-created ZIP instead of an app bundle:

```bash
scripts/release \
  --mind-weaver-app dist/MindWeaver-0.1.1.zip \
  --mind-weaver-version 0.1.1 \
  --upload-mind-weaver-app \
  --create-mind-weaver-release
```

`--upload-mind-weaver-app` uploads to the GitHub release at:

```text
Noswad123/mind-weaver-swift v<version>
```

If that release does not exist yet, add `--create-mind-weaver-release` to create
it before uploading the ZIP. Without that flag, the helper fails with a concise
message instead of a Python traceback.

After release, verify installation/update from the tap:

```bash
brew update
brew upgrade --cask mind-weaver
# or, on a clean machine:
brew install --cask Noswad123/jamal-arcana/mind-weaver
```

### First-time or auth troubleshooting

The first cask release required extra setup because the cask, release artifact,
and GitHub release did not exist yet. Future releases should not need that extra
manual setup.

If `gh release create` fails with a missing `workflow` scope, refresh GitHub CLI
auth for the same GitHub account that owns or can write to
`Noswad123/mind-weaver-swift`:

```bash
gh auth status -h github.com
gh auth refresh -h github.com -s workflow
```

If `gh auth refresh` says it received credentials for a different account, log
out of the wrong account or re-login as the intended one:

```bash
gh auth logout -h github.com
gh auth login -h github.com -p https -s repo,workflow
```

The browser/device flow must complete as the same account shown by
`gh auth status`, otherwise GitHub CLI will refuse to refresh the token.

If the tap repo is dirty while iterating on release tooling, either commit/stash
the changes first or intentionally use:

```bash
scripts/release ... --allow-dirty
```

To release formulae and the app cask together, select both targets:

```bash
scripts/release -t mw -t mind-weaver --mind-weaver-app /path/to/MindWeaver.app
```

The script checks clean working trees, creates and pushes `vX.Y.Z` tags,
downloads the GitHub tag archives to compute formula `sha256` values, updates
`Formula/*.rb` and/or `Casks/*.rb`, commits the tap changes, pushes the tap, and
syncs Homebrew's local tap clone so `brew upgrade <tool>` sees the new version
immediately. Pass `--help` for safety and workflow options such as `--no-push`,
`--no-tap-commit`, `--no-brew-update`, and `--skip-tests`.
