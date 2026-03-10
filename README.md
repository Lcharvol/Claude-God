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
  Circular gauges, cost analytics, sparkline charts, CSV export.<br>
  Free, open source, zero dependencies.
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
| **Quotas** | Circular gauges | Animated ring gauges for session (5h), weekly, Sonnet & Opus quotas |
| | Dynamic icon | Menu bar icon turns green/orange/red based on usage level |
| | Live countdown | Real-time timer showing when quotas reset |
| **Analytics** | Cost tracking | Daily, weekly, monthly cost breakdown from JSONL session files |
| | Sparkline chart | 7-day usage trend with smooth Bezier curves |
| | Model breakdown | Per-model cost and token usage (Opus, Sonnet, Haiku) |
| | Export CSV | Save daily cost & token data as CSV |
| | Copy stats | One-click copy of formatted stats to clipboard |
| **Settings** | Auto-refresh | Configurable interval (1, 2, 5, 10 min) |
| | Compact mode | Minimal UI showing just percentages |
| | Notifications | Alert when usage exceeds configurable threshold |
| | Launch at login | Start automatically with macOS |
| **Design** | Glass cards | Modern UI with hover effects, animated transitions |
| | Dark & Light | Adapts to system appearance automatically |

> **No API key needed.** Uses your existing `claude login` credentials. Works with Pro & Max plans. Completely free.

---

## Quick Start

```bash
# 1. Download & install
open https://github.com/Lcharvol/Claude-God/releases/latest/download/ClaudeGod.dmg

# 2. Allow unsigned app (required once)
xattr -cr /Applications/Claude\ God.app

# 3. Make sure you're logged in
claude login

# 4. Launch — a "C" icon appears in the menu bar
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
├── UsageManager.swift       # OAuth, auto-refresh, notifications, export
├── MenuBarView.swift        # UI: gauges, stats, settings, components
├── SessionAnalyzer.swift    # JSONL parser, cost calculator
└── Assets.xcassets/         # App icon
```

**Zero external dependencies.** Foundation + SwiftUI + Combine + Security + UserNotifications + ServiceManagement.

## Releasing

```bash
git tag v2.2.0 && git push origin v2.2.0
# GitHub Actions builds the .dmg automatically
```

## Roadmap

- [x] Multiple model quotas (Sonnet, Opus, weekly)
- [x] Cost analytics from JSONL files
- [x] Sparkline usage chart
- [x] Export CSV / copy stats
- [x] Circular gauges UI
- [x] Dynamic menu bar icon
- [x] Compact mode
- [ ] Global keyboard shortcut
- [ ] Homebrew cask distribution
- [ ] Usage history persistence

## License

[MIT](LICENSE)
