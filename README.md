<p align="center">
  <img src="https://img.shields.io/github/v/release/Lcharvol/Claude-God?style=flat-square&color=8b6cf6&label=latest" alt="Release">
  <img src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square" alt="Swift 5.9">
  <img src="https://img.shields.io/github/license/Lcharvol/Claude-God?style=flat-square&color=34d399" alt="MIT License">
  <a href="https://github.com/Lcharvol/Claude-God/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Lcharvol/Claude-God/ci.yml?style=flat-square&label=CI" alt="CI"></a>
</p>

<h1 align="center">
  Claude God
</h1>

<p align="center">
  <strong>Monitor your Claude AI usage from the macOS menu bar.</strong><br>
  Real-time quotas, cost analytics, burn rate prediction, project breakdown.<br>
  Free, open source, zero dependencies.
</p>

<p align="center">
  <img src="assets/screenshot-usage.png" width="320" alt="Usage — quota cards with progress bars">
  &nbsp;&nbsp;
  <img src="assets/screenshot-analytics.png" width="320" alt="Analytics — cost breakdown, sparkline, models">
</p>
<p align="center">
  <img src="assets/screenshot-timeline.png" width="320" alt="Timeline — session history with topics and costs">
  &nbsp;&nbsp;
  <img src="assets/screenshot-roi.png" width="320" alt="ROI — return on investment analysis">
</p>
<p align="center">
  <img src="assets/screenshot-extensions-discover.png" width="320" alt="Extensions — discover and install plugins">
  &nbsp;&nbsp;
  <img src="assets/screenshot-extensions-installed.png" width="320" alt="Extensions — manage installed plugins">
</p>

<p align="center">
  <a href="https://github.com/Lcharvol/Claude-God/releases/latest/download/ClaudeGod.dmg"><strong>Download .dmg</strong></a> &nbsp;&middot;&nbsp;
  <a href="https://claudegod.app">Website</a> &nbsp;&middot;&nbsp;
  <a href="https://github.com/Lcharvol/Claude-God/releases">Changelog</a>
</p>

---

## Features

| | Feature | Description |
|---|---|---|
| **Quotas** | Progress bars | Animated bars for session (5h), weekly, Sonnet & Opus quotas |
| | Dynamic icon | Menu bar icon turns green/orange/red based on worst quota |
| | Live countdown | Real-time timer showing when quotas reset |
| | Burn rate | Predicts when you'll hit the limit based on current velocity |
| | Model advisor | Smart tips when quota imbalance is detected |
| **Analytics** | Cost tracking | Daily, weekly, monthly cost breakdown from JSONL session files |
| | Project breakdown | Per-project cost and session count |
| | Session history | Recent conversations with topic, duration, cost, model |
| | Sparkline chart | Interactive usage trend (7/14/30 days) with hover tooltips |
| | Model breakdown | Per-model cost and token usage with totals |
| | Daily budget | Set a $/day target with progress tracking |
| | Export CSV | Save daily cost & token data as CSV |
| | Copy stats | One-click copy of formatted stats to clipboard |
| **Live** | Active session | Detects when Claude Code is running (green dot) |
| | Auto-credentials | File watcher auto-detects `claude login` |
| | Reset notification | Get notified when quotas reset |
| **Settings** | Auto-refresh | Configurable interval (1, 2, 5, 10 min) |
| | Menu bar modes | Icon only, Session %, Timer, All quotas |
| | Compact mode | Minimal UI showing just percentages |
| | Notifications | Alert when usage exceeds configurable threshold |
| | Launch at login | Start automatically with macOS |
| **Extensions** | Plugin marketplace | Browse, search, and install Claude Code plugins directly from the app |
| | Category filter | Filter plugins by category (Development, Productivity, Database, etc.) |
| | Install counts | See plugin popularity with download stats |
| | Manage plugins | Toggle enabled/disabled, uninstall, check for updates |
| | Plugin UI | Installed plugins with custom UI (e.g. claude-mem) open inline detail views |
| **Design** | shadcn/ui style | Flat, minimal, bordered cards with hover effects |
| | Dark & Light | Adapts to system appearance automatically |
| | Accessibility | VoiceOver labels on all interactive elements |

> **No API key needed.** Uses your existing `claude login` credentials. Works with Pro & Max plans. Completely free.

---

## Quick Start

### Homebrew (recommended)

```bash
brew tap lcharvol/tap
brew install --cask claude-god
```

### Manual

```bash
# 1. Download & install
open https://github.com/Lcharvol/Claude-God/releases/latest/download/ClaudeGod.dmg

# 2. Allow unsigned app (required once)
xattr -cr /Applications/Claude\ God.app
```

### Then

```bash
# Make sure you're logged in
claude login

# Launch — a "C" icon appears in the menu bar, press ⌥⌘C to toggle
open /Applications/Claude\ God.app
```

---

## How It Works

**Quotas** — The app reads your OAuth credentials from `claude login` (Keychain or `~/.claude/.credentials.json`) and calls:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth_token>
anthropic-beta: oauth-2025-04-20
```

Returns utilization for each quota window (`five_hour`, `seven_day`, `seven_day_sonnet`, `seven_day_opus`). Tokens are refreshed automatically.

**Cost Analytics** — Parses all `~/.claude/projects/**/*.jsonl` session files to calculate costs per model using Anthropic's published pricing.

---

## Build from Source

```bash
git clone https://github.com/Lcharvol/Claude-God.git
cd Claude-God
brew install xcodegen    # one time
make build               # or: make open (Xcode)
```

See [`Makefile`](Makefile) for all commands: `build`, `run`, `dmg`, `clean`.

## Project Structure

```
Sources/
├── ClaudeUsageApp.swift     # Entry point, MenuBarExtra
├── UsageManager.swift       # OAuth, auto-refresh, notifications, budget, active session
├── AuthManager.swift        # Credential loading, token refresh, file watcher
├── UpdateChecker.swift      # GitHub releases auto-update
├── HotkeyManager.swift      # Global ⌥⌘C hotkey (Carbon API)
├── AppShortcuts.swift       # Shortcuts.app intents (Get Usage, Get Cost, Refresh)
├── MenuBarView.swift        # UI: cards, stats, settings, heatmap, shadcn components
├── SessionAnalyzer.swift    # JSONL parser, cost calculator, efficiency metrics
└── Assets.xcassets/         # App icon
Widget/
└── ClaudeGodWidget.swift    # WidgetKit — desktop quota gauges
```

**Zero external dependencies.** Foundation + SwiftUI + Combine + Security + UserNotifications + ServiceManagement.

## Releasing

```bash
git tag v2.8.0 && git push origin v2.8.0
# GitHub Actions builds the .dmg automatically
```

## Changelog

### v2.24.3
- **Fixed**: Transparent phantom window when changing text size — `WindowTopAnchor` only resized the `NSPanel`'s height, so SwiftUI's content resize on textScale change left an empty backing halo (or overflowed the window). Anchor now resizes width too and keeps the top-right corner fixed so the popover stays anchored under its status item

### v2.24.2
- **Fixed**: "Sign In" button in Settings appeared to do nothing on a fresh install — clicking it flashed "Signing in..." briefly then silently reverted. The error message ("Claude CLI not found — install with `npm i -g @anthropic-ai/claude-code`") was set correctly but was only rendered in the Usage-tab error banner, which fresh-install users never see (they're routed straight to Settings by the `!isAuthenticated` gate). The Authentication card now displays the error under the Sign In button

### v2.24.1
- **Fixed**: Intel Mac support restored — the release DMG is now a universal binary (arm64 + x86_64). The GitHub Actions Apple Silicon runner was producing arm64-only builds that Intel users couldn't launch; added `ARCHS="arm64 x86_64"` + `ONLY_ACTIVE_ARCH=NO` to the workflow, no source changes needed ([#34](https://github.com/Lcharvol/Claude-God/issues/34), thanks @kelvincht)

### v2.24.0
- **Added**: Adjustable popover text size (S / M / L / XL) — new preset picker in Settings resizes every font in the popover via a `textScale` environment value + `.shFont(...)` view modifier (no `.scaleEffect` blur). Popover width scales with the multiplier so bigger type doesn't wrap. Menu bar untouched; default `M` (1.0) leaves existing users unchanged ([#33](https://github.com/Lcharvol/Claude-God/issues/33), [#39](https://github.com/Lcharvol/Claude-God/pull/39), thanks @nairdaleo)
- **Added**: Model-scoped weekly quotas surfaced in the usage list — `weekly_scoped` entries from the OAuth `limits` array (currently the **Fable** weekly quota on Max+) now render as `"Weekly (<name>)"` alongside the existing "Weekly (all)" row, and downstream code (notifications, alert rules, rings, widget) picks them up generically ([#36](https://github.com/Lcharvol/Claude-God/pull/36), thanks @pieropalevsky)
- **Fixed**: Permanent "Session expired" that no sign-in could clear — two combined bugs: credential loaders returned `~/.claude/.credentials.json` without checking expiry (pinning the app to a dead token while a valid one sat in the Keychain), and the embedded `claude auth login` PTY had no stdin write path so the "paste your authorization code" prompt was unanswerable. Both entry points now delegate to a single `resolveCredentials` that picks whichever source has the latest `expiresAt`, and `TerminalSession.send(_:)` adds a line-buffered write to the PTY master with a monospaced input row in the sign-in view ([#37](https://github.com/Lcharvol/Claude-God/issues/37), [#38](https://github.com/Lcharvol/Claude-God/pull/38))

### v2.23.4
- **Fixed**: Repeated "Claude God wants to use your confidential information stored in `Claude Code-credentials-XXXXXXXX`" prompt — newer Claude Code versions write credentials under suffixed service names, and the per-entry data fetch in `loadBestKeychainEntryWithPrefix` used `SecItemCopyMatching + kSecReturnData`, which prompts on every read. The fetch now reuses the existing `security find-generic-password` helper with the exact service name discovered from the non-prompting list query, so the dialog loop disappears ([#30](https://github.com/Lcharvol/Claude-God/issues/30), [#31](https://github.com/Lcharvol/Claude-God/pull/31), thanks @nairdaleo)

### v2.23.3
- **Fixed**: No more "Claude God wants to access the keychain" prompt for the common case — v2.23.2's fallback hit the Security framework API directly (which prompts the first time an ad-hoc-signed app reads an item it didn't create). Now tries `security find-generic-password -a $USER` as a second non-prompting fast path before the API; the scan only runs for unusual multi-account layouts

### v2.23.2
- **Fixed**: PR #27 Keychain fallback actually works now — the scan called `SecItemCopyMatching` with an attribute combination (`kSecReturnAttributes + kSecReturnData + kSecMatchLimitAll`) that returns `errSecParam (-50)` on the legacy login keychain, so it bailed out before reading anything. Now lists refs+attributes first, then fetches each item's data with a per-item query, so users with multiple `Claude Code-credentials` entries (Claude Code stores `account=unknown` next to `account=<user>`) finally connect

### v2.23.1
- **Fixed**: Embedded `claude auth login` no longer crashes the app — PTY slave FD was being closed twice (after the first close, the OS reused that FD slot for a guarded keychain socket, then the handle's dealloc triggered `EXC_GUARD`); slave handle now uses `closeOnDealloc: false` ([#26](https://github.com/Lcharvol/Claude-God/issues/26), [#27](https://github.com/Lcharvol/Claude-God/pull/27), thanks @nairdaleo)
- **Fixed**: Credentials detected when only per-project Keychain entries exist — newer Claude Code writes suffixed entries (`Claude Code-credentials/path/...`) and may leave the base entry stale, so signed-in users appeared "Not connected"; `AuthManager` now scans all `Claude Code-credentials*` items as a fallback
- **Fixed**: Popover only grows downward when resizing — new `WindowTopAnchor` pins the top edge to the status bar item in Release/Homebrew builds (was resizing from the center)

### v2.23.0
- **New**: Extra Usage (dollar budget) is now a first-class quota across the app — surfaced as a % in every menu bar mode (including `E X%` in "All" mode), selectable as a ring in Icon+ Rings, drives icon warning/critical colors, and fires standard + custom usage alerts. The popover's Extra Usage card gains a color-coded progress bar when a monthly limit is set ([#25](https://github.com/Lcharvol/Claude-God/pull/25), thanks @ecoffey)

### v2.22.2
- **Changed**: Peak hours window updated to Mon–Fri 5am–11am PT to match Anthropic's actual throttling band for 5-hour session limits (was 7am–5pm PT) ([#24](https://github.com/Lcharvol/Claude-God/pull/24), thanks @pieropalevsky)
- **Refactored**: Tooltips derive from a single `peakHoursDescription` source-of-truth so future policy changes touch one constant instead of three sites

### v2.22.1
- **Fixed**: OAuth token self-refresh — now sends `application/x-www-form-urlencoded` per RFC 6749, ending the HTTP 400 loop on silent refresh ([#21](https://github.com/Lcharvol/Claude-God/issues/21), [#22](https://github.com/Lcharvol/Claude-God/pull/22))
- **Fixed**: `claude` binary resolution — falls back to `$SHELL -l -c "which claude"` so nvm / fnm / volta / pnpm installs are found
- **Fixed**: Auto-recovery after manual `claude auth login` — 10s background poller picks up Keychain-only credential writes without needing Sign In

### v2.22.0
- **New**: Rings menu bar mode — Apple Watch-style concentric activity rings for up to 3 quotas, configurable picker + live preview, optional Timer ring ([#20](https://github.com/Lcharvol/Claude-God/pull/20))

### v2.21.1
- **Fixed**: Drastic energy savings — App Nap re-enabled, adaptive countdown, slower active-session polling, JSONL scan deferred to popover open ([#14](https://github.com/Lcharvol/Claude-God/issues/14))
- **Fixed**: Widget extension now registers — added missing `NSExtensionPointIdentifier` ([#13](https://github.com/Lcharvol/Claude-God/issues/13))
- **Fixed**: Resizable popover actually responds to drag — visible grip handle replaces the broken NSWindow wiring

### v2.21.0
- **New**: Session+Week menu bar mode — session %, reset countdown, and weekly % at a glance ([#15](https://github.com/Lcharvol/Claude-God/issues/15))
- **New**: Resizable window with persisted height
- **New**: Extra usage balance card + Claude Design quota row
- **New**: Sign In button + opt-in auto-reconnect when OAuth token expires
- **Fixed**: Usage tab flicker on expired token, long reset times shown as days/hours

### v2.20.4
- **Fixed**: Hardened refresh pipeline — every exit path clears loading state, credential reload timeouts, backoff counter auto-resets

### v2.20.3
- **Fixed**: Respect `Retry-After` header on 429, progressive backoff, token expiry pre-flight, Keychain fallback for credentials

### v2.20.2
- **Fixed**: App no longer gets stuck on "Rate limited" screen after `claude login` ([#5](https://github.com/Lcharvol/Claude-God/issues/5))
- **Fixed**: Credential changes now trigger auto-refresh even when an error is displayed

### v2.20.1
- **Fixed**: Refresh no longer gets stuck — cancellable fetches, stale response detection, centralized state reset
- **New**: Peak / off-peak indicator with countdown to transition

### v2.19.0
- **Perf**: JSONL parsing without Data→String roundtrip, SQLite 9→4 queries, widget skip unchanged, keychain off main thread

### v2.18.0
- **New**: GitHub, swift-lsp, code-review, code-simplifier, context7, playwright plugin detail views (9 total)
- **Fixed**: Menu bar icon contrast, font sizes +1pt, wider window

### v2.17.0
- **New**: Superpowers plugin UI — browse skills, view plans with progress, design specs
- **New**: Frontend Design plugin UI — design principles, aesthetic tones, anti-patterns, cookbook link

### v2.16.0
- **New**: Extensions tab with plugin marketplace — browse, install, and manage Claude Code plugins directly from the app
- **New**: Featured plugin cards for plugins with custom UI (claude-mem opens inline Memory panel)

### v2.15.0
- **Fixed**: Memory tab now reads correct claude-mem schema (`observations` table)
- **New**: Activity timeline, project summaries, Markdown export, delete observations, open files in Finder

### v2.14.0
- **New**: Memory tab — browse claude-mem persistent memories with search, project filter, and install guide

### v2.13.1
- **Fix**: OAuth token refresh no longer persists tokens — prevents daily 401 errors

### v2.13.0
- **Perf**: Single JSON decode per JSONL line, direct Data line splitting, single-pass file traversal, binary search for ROI matching

### v2.12.0
- **Improved**: Logging, error handling, forecasting, and exports

### v2.11.0
- **New**: ROI tab — correlates git commits with Claude sessions (cost/commit, per-project, per-model, 30-day trend)

### v2.10.0
- **New**: Updated model pricing, landing page SEO, download counter
- **Fix**: Project cost truncation, mobile layout, 429 handling

### v2.9.0
- **Fix**: Token refresh race condition, notification spam, reset timer, CSV export, duplicate alert rules

### v2.8.0
- **New**: Desktop widget, usage heatmap, live session cost, per-project budgets, Shortcuts.app, multi-account, custom alerts

[Full changelog →](CHANGELOG.md)

## License

[MIT](LICENSE)
