# Claude God

A lightweight macOS menu bar app that monitors your Claude usage quotas in real time. Works with **Pro** and **Max** plans — no API credits needed.

[![CI](https://github.com/Lcharvol/Claude-God/actions/workflows/ci.yml/badge.svg)](https://github.com/Lcharvol/Claude-God/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Lcharvol/Claude-God)](https://github.com/Lcharvol/Claude-God/releases/latest/download/ClaudeGod.dmg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Download

**[Download the latest .dmg](https://github.com/Lcharvol/Claude-God/releases/latest/download/ClaudeGod.dmg)** — no Xcode required.

1. Open the `.dmg`, drag **Claude God** to Applications
2. First launch — open Terminal and run:
   ```bash
   xattr -cr /Applications/Claude\ God.app
   ```
   *(required once because the app is not notarized)*
3. Make sure you're logged in to Claude Code:
   ```bash
   claude login
   ```
4. Launch the app — a `C` icon appears in the menu bar

## Features

- **No API key needed** — uses your existing `claude login` credentials
- **Works with Pro & Max** — detects your subscription type automatically
- **Multiple quotas** — session (5h), weekly (7d), per-model (Sonnet, Opus)
- **Menu bar native** — always visible, no dock icon, no window
- **Auto-refresh** — configurable interval (1, 2, 5, 10 min or off)
- **Live countdown** — see exactly when quotas reset
- **Color-coded bars** — green/orange/red at a glance
- **Notifications** — alert when usage gets high
- **Launch at login** — start automatically with your Mac
- **Completely free** — no API credits, no billing, zero cost
- **Fully private** — no server, no telemetry, no tracking

## How it works

The app reads your OAuth credentials from `claude login` (stored in macOS Keychain or `~/.claude/.credentials.json`) and calls Anthropic's usage API:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth_token>
anthropic-beta: oauth-2025-04-20
```

This returns your quota utilization for each window:

| Field | Info |
|---|---|
| `five_hour.utilization` | Session usage (resets every 5h) |
| `seven_day.utilization` | Weekly usage (all models) |
| `seven_day_sonnet.utilization` | Sonnet-specific weekly usage |
| `seven_day_opus.utilization` | Opus-specific weekly usage |

OAuth tokens are automatically refreshed when they expire.

## Build from source

Requires macOS 13+ and Xcode 15+.

```bash
git clone https://github.com/Lcharvol/Claude-God.git
cd Claude-God
brew install xcodegen    # one time
make build               # or: make open (opens in Xcode)
```

See the [Makefile](Makefile) for all commands: `make build`, `make run`, `make dmg`, `make clean`.

## Project structure

```
Claude-God/
├── Sources/
│   ├── ClaudeUsageApp.swift       # App entry point, MenuBarExtra
│   ├── UsageManager.swift         # OAuth API, auto-refresh, notifications
│   ├── MenuBarView.swift          # UI: quotas, settings, controls
│   ├── KeychainHelper.swift       # Keychain utilities
│   └── ClaudeGod.entitlements     # Network permissions
├── docs/
│   ├── index.html                 # Landing page (claudegod.app)
│   └── CNAME                      # Custom domain config
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                 # Build check on push & PRs
│   │   └── build.yml              # Release: build DMG on tag push
│   ├── ISSUE_TEMPLATE/            # Bug report & feature request templates
│   └── pull_request_template.md
├── project.yml                    # Xcodegen spec
├── Makefile                       # Build commands
├── CHANGELOG.md                   # Version history
└── LICENSE                        # MIT
```

**Zero external dependencies.** Only Foundation, SwiftUI, Combine, Security, UserNotifications, and ServiceManagement.

## Releasing

Push a tag and GitHub Actions builds the `.dmg` automatically:

```bash
git tag v2.0.0
git push origin v2.0.0
```

## Roadmap

- [x] Track multiple models (different quotas per model)
- [ ] Usage history graph
- [ ] Global keyboard shortcut to open popover
- [ ] Homebrew cask distribution

## License

[MIT](LICENSE)
