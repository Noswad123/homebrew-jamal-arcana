# Homebrew Jamal Arcana

Homebrew tap for Jamal Arcana tools.

## Install

```bash
brew tap Noswad123/jamal-arcana
brew install coven
brew install mw
brew install wisp
brew install waystone
```

Or install directly:

```bash
brew install Noswad123/jamal-arcana/coven
brew install Noswad123/jamal-arcana/mw
brew install Noswad123/jamal-arcana/wisp
brew install Noswad123/jamal-arcana/waystone
```

## Formulae

- `coven` — create and operate magic-themed multi-agent workspaces
- `mw` — local-first notes and todos CLI
- `wisp` — open a command in a floating kitty terminal window
- `waystone` — save, fuzzy-pick, copy, and open frequently used paths

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

The script checks clean working trees, creates and pushes `vX.Y.Z` tags,
downloads the GitHub tag archives to compute `sha256`, updates `Formula/*.rb`,
commits the formula changes, pushes the tap, and syncs Homebrew's local tap
clone so `brew upgrade <tool>` sees the new version immediately. Pass `--help`
for safety and workflow options such as `--no-push`, `--no-tap-commit`,
`--no-brew-update`, and `--skip-tests`.
