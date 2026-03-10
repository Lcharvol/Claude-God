# Claude God

A lightweight macOS menu bar app that monitors your Anthropic API rate limits in real time.

[![CI](https://github.com/Lcharvol/Claude-God/actions/workflows/ci.yml/badge.svg)](https://github.com/Lcharvol/Claude-God/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Lcharvol/Claude-God)](https://github.com/Lcharvol/Claude-God/releases/latest/download/ClaudeGod.dmg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

## Download

**[Download the latest .dmg](https://github.com/Lcharvol/Claude-God/releases/latest/download/ClaudeGod.dmg)** — no Xcode required.

1. Open the `.dmg`, drag **Claude God** to Applications
2. Launch it — a `C` icon appears in the menu bar
3. Click the icon, paste your [Anthropic API key](https://console.anthropic.com/), hit Save

That's it.

## Features

- **Menu bar native** — always visible, no dock icon, no window
- **Auto-refresh** — configurable interval (1, 2, 5, 10 min or off)
- **Live countdown** — see exactly when rate limits reset
- **Color-coded bars** — green/orange/red at a glance
- **Notifications** — alert when tokens drop below a configurable threshold
- **Keychain storage** — API key encrypted by macOS, not plain text
- **Launch at login** — start automatically with your Mac
- **Near-zero cost** — each refresh uses 1 Haiku token (~$0.00001)
- **Fully private** — no server, no telemetry, no tracking

## How it works

The app sends a minimal API request (1 token) and reads the rate limit headers Anthropic returns:

| Header | Info |
|---|---|
| `anthropic-ratelimit-tokens-limit` | Max tokens per window |
| `anthropic-ratelimit-tokens-remaining` | Tokens left |
| `anthropic-ratelimit-tokens-reset` | When the limit resets |
| `anthropic-ratelimit-requests-limit` | Max requests per window |
| `anthropic-ratelimit-requests-remaining` | Requests left |

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
│   ├── UsageManager.swift         # API calls, auto-refresh, notifications
│   ├── MenuBarView.swift          # UI: settings, usage bars, controls
│   ├── KeychainHelper.swift       # Secure API key storage
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
git tag v1.1.0
git push origin v1.1.0
```

## Roadmap

- [ ] Track multiple models (different rate limits per model)
- [ ] Usage history graph
- [ ] Global keyboard shortcut to open popover
- [ ] Homebrew cask distribution

## License

[MIT](LICENSE)
