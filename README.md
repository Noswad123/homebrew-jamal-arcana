# Homebrew Jamal Arcana

Homebrew tap for Jamal Arcana tools.

## Install

Install or update the whole tap-managed ecosystem from this repo's manifest:

```bash
brew install Noswad123/jamal-arcana/arcana
arcana install
arcana update
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

`doctor` also reports whether managed formulae/casks are missing or stale.

Or install tools individually:

```bash
brew tap Noswad123/jamal-arcana
brew install arcana
brew install coven
brew install djinn
brew install kitsune
brew install mw
brew install wisp
brew install waystone
brew install --cask mind-weaver
```

Or install directly:

```bash
brew install Noswad123/jamal-arcana/arcana
brew install Noswad123/jamal-arcana/coven
brew install Noswad123/jamal-arcana/djinn
brew install Noswad123/jamal-arcana/kitsune
brew install Noswad123/jamal-arcana/mw
brew install Noswad123/jamal-arcana/wisp
brew install Noswad123/jamal-arcana/waystone
brew install --cask Noswad123/jamal-arcana/mind-weaver
```

## Formulae

- `arcana` — install and update the Jamal Arcana Homebrew ecosystem
- `coven` — create and operate magic-themed multi-agent workspaces
- `djinn` — local-first companion for OpenCode and other AI coding agents
- `kitsune` — composable multiplexer kits for named working sessions
- `mw` — local-first notes and todos CLI
- `wisp` — open a command in a floating kitty terminal window
- `waystone` — save, fuzzy-pick, copy, and open frequently used paths

## Casks

- `mind-weaver` — native macOS app shell for MindWeaver

`arcana`, `coven`, `djinn`, and `kitsune` currently track the `main` branch until their first tagged releases.
`arcana update` reinstalls those branch-tracking tools so local installs pick up
new commits even when their formula version is unchanged.

## MindWeaver native app dependency strategy

The native MindWeaver macOS app is intentionally a SwiftUI shell around the Go
`mw` engine. Homebrew should provide the required CLI dependency instead of the
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
