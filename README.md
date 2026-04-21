# Current

A macOS menu bar app that surfaces available updates across the package
managers you actually use (Homebrew, npm globals, pnpm globals, more to
come) and lets you apply them with one click.

## Status

Early scaffold. Brew / npm / pnpm providers wired; UI works end-to-end
for check + sequential batch upgrade with queued / running / done /
failed states.

## Requirements

- macOS 14+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build & run

```sh
xcodegen generate
open Current.xcodeproj
# ⌘R in Xcode
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -project Current.xcodeproj -scheme Current -configuration Debug build
open build/Debug/Current.app   # adjust path to your DerivedData if needed
```

## Architecture

```
Sources/Current/
├── App.swift                 # @main, MenuBarExtra entry
├── Models/
│   ├── UpdateItem.swift      # one outdated package
│   └── RowStatus.swift       # idle / queued / running / success / failure
├── Core/
│   ├── Shell.swift           # spawn tools via `zsh -ilc` (inherits user PATH)
│   └── UpdateManager.swift   # @MainActor state, refresh, queue, persistence
├── Providers/
│   ├── UpdateSource.swift    # protocol
│   ├── BrewSource.swift      # `brew outdated --json=v2`
│   ├── NpmSource.swift       # `npm outdated -g --json`
│   └── PnpmSource.swift      # `pnpm outdated -g --format json`
└── Views/
    ├── RootView.swift
    ├── Header.swift
    ├── Footer.swift
    └── UpdateRow.swift       # per-package row with inline log + context menu
```

### Adding a provider

Conform to `UpdateSource`, register it in `UpdateManager.sources`.

## Design notes

- **`LSUIElement = true`** — menu bar only, no Dock icon.
- **App Sandbox off** — we spawn the user's package manager binaries.
- **PATH** — every command runs through `/bin/zsh -ilc "…"` so tools
  installed by Homebrew / nvm / mise resolve exactly like they do in
  Terminal.
- **Cask greediness** — `brew outdated` runs without `--greedy`, so casks
  that auto-update themselves (Chrome, Slack, etc.) don't spam the list.
- **Skip** remembers a specific version; a newer version auto-unskips.
- **Ignore** is permanent until the user un-ignores from preferences
  (preferences UI still TODO).
- **Batch upgrades are sequential** (brew / npm dislike concurrent
  writes). Queued items show a clock icon, running shows a spinner,
  done shows a green check for ~1s before the row clears.
