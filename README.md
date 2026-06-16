# Homebrew Jamal Arcana

Homebrew tap for Jamal Arcana tools.

## Install

```bash
brew tap Noswad123/jamal-arcana
brew install coven
brew install mw
brew install wisp
brew install waystone
brew install --cask mind-weaver
```

Or install directly:

```bash
brew install Noswad123/jamal-arcana/coven
brew install Noswad123/jamal-arcana/mw
brew install Noswad123/jamal-arcana/wisp
brew install Noswad123/jamal-arcana/waystone
brew install --cask Noswad123/jamal-arcana/mind-weaver
```

## Formulae

- `coven` — create and operate magic-themed multi-agent workspaces
- `mw` — local-first notes and todos CLI
- `wisp` — open a command in a floating kitty terminal window
- `waystone` — save, fuzzy-pick, copy, and open frequently used paths

## Casks

- `mind-weaver` — native macOS app shell for MindWeaver

`coven` currently tracks the `main` branch until its first tagged release.

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

When a cask is added for the native app, it should declare `mw` as its required
formula dependency and leave `wisp`, `neovim`, `kitty`, and `aerospace` as
documented optional enhancements.

The cask expects a signed/notarized release ZIP named with this convention:

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

Before publishing a cask update, replace `sha256 :no_check` in
`Casks/mind-weaver.rb` with the real checksum:

```bash
shasum -a 256 MindWeaver-0.1.0.zip
```

## Release formulae

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

Release/update only the MindWeaver app cask from an exported archive:

```bash
scripts/release \
  --mind-weaver-app /path/to/MindWeaver.app \
  --mind-weaver-version 0.1.0 \
  --no-tap-commit
```

If the input is a `.app` bundle, the helper creates:

```text
dist/MindWeaver-<version>.zip
```

using `ditto -c -k --keepParent`, computes its SHA256, and updates
`Casks/mind-weaver.rb`. If the input is already a ZIP, it computes the checksum
directly. The helper prints the `gh release upload ...` command unless upload is
enabled explicitly:

```bash
scripts/release \
  --mind-weaver-app dist/MindWeaver-0.1.0.zip \
  --upload-mind-weaver-app
```

`--upload-mind-weaver-app` expects an existing GitHub release at:

```text
Noswad123/mind-weaver-swift v<version>
```

To release formulae and the app cask together, select both targets:

```bash
scripts/release -t mw -t mind-weaver --mind-weaver-app /path/to/MindWeaver.app
```

The script checks clean working trees, creates and pushes `vX.Y.Z` tags,
downloads the GitHub tag archives to compute formula `sha256` values, updates
`Formula/*.rb` and/or `Casks/*.rb`, commits the tap changes, pushes the tap, and syncs Homebrew's local tap
clone so `brew upgrade <tool>` sees the new version immediately. Pass `--help`
for safety and workflow options such as `--no-push`, `--no-tap-commit`,
`--no-brew-update`, and `--skip-tests`.
