# Current — project notes

Living doc for things we've decided, things we've deferred, and open
questions. Keep short.

## Done

- [x] Menu bar app via `NSStatusItem` + `NSPopover` (replaced
      `MenuBarExtra` because we need a right-click menu on the bar icon).
- [x] Pluggable `UpdateSource` protocol. Providers: `brew`, `npm -g`,
      `pnpm -g`.
- [x] `Shell` helper runs every tool through `zsh -ilc` so PATH matches
      Terminal (Homebrew, nvm, mise, etc. all resolve).
- [x] Check flow: parallel across sources, per-source availability
      tracked (`available` / `disabled` / `unavailable`).
- [x] Upgrade flow: sequential batch. Row states:
      `idle → queued → running → success / failure`.
- [x] Inline per-row log (expand/collapse via chevron, or Log button
      while running/failed).
- [x] Skip version (auto-unskipped when a newer version ships).
- [x] Ignore package (persists until removed from Preferences).
- [x] Stats: append-only upgrade log, summary of "this week" / "all
      time" / "failed", capped at 1000 entries. Surfaced in the footer
      and the right-click menu.
- [x] Source text badge (colored pill with `brew` / `npm` / `pnpm`).
- [x] Preferences window (tabs: General with Sources, Ignored Packages,
      Skipped Versions).
- [x] Right-click on the menu bar icon: Refresh Packages, Preferences…,
      Statistics line, Version, Quit — all with SF Symbol icons where
      appropriate.
- [x] `Update All` button with leading `arrow.down.circle.fill` icon,
      default-action keyboard shortcut, count in label.
- [x] Stable relative timestamp in header (`just now`, `5 min ago`,
      `2 hours ago`) that doesn't tick.

## Architecture snapshot

```
Sources/Current/
├── App.swift                       # @main + NSApplicationDelegateAdaptor
├── Core/
│   ├── AppDelegate.swift           # NSStatusItem, popover, right-click menu, prefs window
│   ├── Shell.swift                 # zsh -ilc wrapper (run + stream)
│   ├── UpdateManager.swift         # @MainActor state, refresh/queue, stats, persistence
│   ├── StatsStore.swift            # upgrade history in UserDefaults
│   └── RelativeTime.swift          # stable "2 min ago" formatter
├── Models/
│   ├── UpdateItem.swift
│   ├── RowStatus.swift
│   └── SourceStatus.swift          # SourceState + availability enum
├── Providers/
│   ├── UpdateSource.swift          # protocol + CheckOptions
│   ├── BrewSource.swift
│   ├── NpmSource.swift
│   └── PnpmSource.swift
└── Views/
    ├── RootView.swift              # popover layout
    ├── Header.swift                # title + count + last-checked + refresh + prefs gear
    ├── Footer.swift                # stats (left) + Update All (right)
    ├── UpdateRow.swift             # per-package row (Ignore / Skip / Update)
    └── PreferencesView.swift       # tabbed prefs window
```

## Known issues / UX fixes

Small stuff to fix, not full features. Roughly in priority:

- [ ] **Completed rows vanish instantly.** After an upgrade succeeds
      the row removes itself ~1.2s later, which jumps the list and
      yanks the log away if the user was reading it. Keep the row in
      place as a "done" state (green check + `from → to` version). Log
      stays visible and dismissible. Clear happens only on next refresh
      or via an explicit "Clear completed" control.
- [ ] **Installs aren't cancelable.** Three levels:
  1. **Queued** items: clicking the row (or a small ×) pulls them out
     of the queue. Visual hint: queue icon becomes an × on hover.
  2. **Update All** button while batch is running should flip to "Stop
     & Clear Queue" and on click cancel everything still queued. The
     currently-running item finishes on its own — interrupting
     `brew upgrade` mid-flight is risky.
  3. (Maybe) currently-running upgrade: send SIGTERM to the `Process`.
     Only worth it if the tool has hung; document the risk.
- [ ] **Empty state should be a dedicated compact layout.** When there
      are no visible updates, drop the footer entirely and render only
      the "You're all caught up" card with the stats line moved into
      it. Probably shrink popover height too so the menu doesn't feel
      empty.
- [ ] **Refresh causes a few-pixel vertical shift.** Pressing Refresh
      swaps the `arrow.clockwise` button for a `ProgressView` whose
      intrinsic height differs slightly, pushing the header down. Fix
      by pinning a fixed frame on that slot, or wrap in a container
      with reserved height.
- [ ] **Don't swap the menu bar icon during refresh.** Currently it
      flips between `shippingbox` and `arrow.triangle.2.circlepath`
      which is distracting. Keep the box. If we want a refresh signal,
      use a subtle badge/opacity change instead.

## Deferred — in rough priority order

### 1. Click a package → open its source site

- [ ] Clicking the package name (or a dedicated link icon) opens the
      upstream homepage / repo.

Cheapest path:

- **brew**: `brew info --json=v2 <name>` → `homepage` (both formulae
  and casks have this). One shell call, cache the result per package.
- **npm**: `npm view <name> homepage` — falls back to
  `repository.url` if `homepage` is missing.
- **pnpm**: same as npm (`pnpm view <name> homepage`).
- **bun** (future): use the npm registry directly
  (`https://registry.npmjs.org/<name>`) since bun doesn't expose
  metadata.

Cache in `~/Library/Caches/com.elias.current/homepages.json` so we
don't shell out on every click. UI: entire row name becomes a
link-styled hover, or a small `arrow.up.forward.square` icon next to
the chevron. Open via `NSWorkspace.shared.open(url)`.

Strict subset of the release-notes work below — ship this first.

### 2. Release notes

- [ ] "View release notes" link on each row that pulls the changelog
      between `currentVersion` and `latestVersion`.

Proposed approach (cheapest wins first):

- **GitHub Releases** is the 80% answer. For any package we can map to
  a GitHub repo, hit
  `GET https://api.github.com/repos/:owner/:repo/releases` and filter
  tags between current and latest (semver-aware). Render the markdown
  inline in the expanded row.
- **How to find the repo per source:**
  - `brew info --json=v2 <name>` → `urls.stable.url` / `homepage` /
    `head.url`.
  - `npm view <pkg> repository.url` → often `git+https://github.com/...`.
  - `pnpm view <pkg> repository.url` → same shape.
  - casks: mostly not GitHub; fall back to `homepage`.
- **Caching:** `~/Library/Caches/com.elias.current/release-notes/<sourceId>/<name>/<version>.md`.
- **Rate limits:** GitHub unauthenticated is 60 req/h. Add optional PAT
  in Preferences if it becomes a problem.
- **Fallbacks:** no GitHub repo → "View on homepage / npm / cask page".
  Multi-version jumps → concatenate releases with headings.
- **UI:** expand-in-place inside the row next to the log. Markdown via
  `AttributedString(markdown:)`, no dependency.

MVP: GitHub-backed only.

### 3. More providers

Each is a ~50-line file conforming to `UpdateSource`.

- [ ] **bun**: `bun pm ls -g` then compare against registry
      (`bun x npm view <pkg> version`). No native "outdated".
- [ ] **mise**: `mise outdated` (JSON). Respects user plugins.
- [ ] **cargo**: `cargo install --list` + `cargo search` or
      `cargo-outdated` if installed.
- [ ] **pipx**: `pipx list --json` + PyPI JSON API.
- [ ] **mas** (Mac App Store): `mas outdated`.
- [ ] **rustup**, **gem**.

### 4. Preferences polish

- [ ] Reorder / drag-to-prioritize sources.
- [ ] Auto-refresh at a specific time of day (e.g. 9am weekdays)
      instead of "every N hours".
- [ ] Per-source greedy option (today it's brew-specific).
- [ ] "Check at launch" toggle.

### 5. Notifications

- [ ] Opt-in banner when updates are found after a background refresh.
      Needs `UNUserNotificationCenter` authorization. Default: off.

### 6. Launch at login

- [ ] `SMAppService.mainApp.register()` on first-run prompt, plus a
      toggle in Preferences → General.

### 7. Full log viewer

Per-row logs are done. Missing:

- [ ] A **global "Logs" button** in the popover header (next to
      Refresh / gear) that opens a full log window with every upgrade's
      output concatenated, searchable.
- [ ] The same view also surfaced as a **Logs tab** in Preferences, so
      you can grep historic failures without opening the popover.
- [ ] Persist the last N log sessions on disk so history survives
      relaunches.

### 8. Design polish

- [ ] Custom app icon + monochrome template menu bar icon.
- [ ] Hover affordances on rows + focus ring.
- [ ] Theming: default, compact, dense. The 340×480 popover is fine but
      could be resizable.

### 9. Packaging & distribution

- [ ] Developer ID signing + notarization (we're unsandboxed and spawn
      subprocesses — Gatekeeper will block unsigned builds for other
      users).
- [ ] Homebrew cask (`brew install --cask current`) once signed.
- [ ] Sparkle integration so Current updates itself. Yes, the updater
      is part of the thing it's updating.

## Decisions made, worth not re-litigating

- **Unsandboxed** — we spawn user package managers; sandbox is
  incompatible.
- **Sequential batch upgrades** — brew/npm hate parallel writes.
- **`zsh -ilc`** over manual PATH munging — matches user's Terminal
  exactly, handles nvm/mise/rbenv correctly.
- **UserDefaults for persistence** — small data, no need for SQLite.
- **`NSStatusItem` over `MenuBarExtra`** — needed for right-click menu
  on the bar icon itself.
- **Brew `--greedy` off by default** — casks with Sparkle updaters
  don't spam the list.
- **No context menu on rows** — actions live inline next to Update.
- **Ignore icon always visible (subtle)** — tried hover-reveal, caused
  layout shift; reverted to always-visible borderless `bell.slash`.
- **Per-row Update is `.bordered`, not `.borderedProminent`** —
  too much blue across many rows; only `Update All` in the footer is
  prominent.
