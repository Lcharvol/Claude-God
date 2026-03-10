# Claude God

A lightweight macOS menu bar app that monitors your Anthropic API rate limits in real time.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-MenuBarExtra-purple)
![License](https://img.shields.io/badge/license-MIT-green)

## What it does

Claude God sits in your macOS menu bar and shows how much API capacity you have left before hitting Anthropic's rate limits.

**Menu bar:** displays a `C` icon with your remaining token percentage.

**Click to expand:**
- Token usage with color-coded progress bar (green/orange/red)
- Request usage with progress bar
- Live countdown until rate limit resets
- One-click refresh
- API key management

## Download

**[Download the latest .dmg](https://github.com/Lcharvol/Claude-God/releases/latest)** — no Xcode required.

1. Open the `.dmg`
2. Drag **Claude God** to your Applications folder
3. Launch it — click the `C` icon in the menu bar
4. Paste your [Anthropic API key](https://console.anthropic.com/) and hit Save

That's it.

## How it works

The app sends a minimal API request (1 token via Haiku, cost ~$0.00001) and reads the rate limit headers that Anthropic returns with every response:

| Header | What it tells us |
|---|---|
| `anthropic-ratelimit-tokens-limit` | Max tokens per window |
| `anthropic-ratelimit-tokens-remaining` | Tokens left |
| `anthropic-ratelimit-tokens-reset` | When the limit resets |
| `anthropic-ratelimit-requests-limit` | Max requests per window |
| `anthropic-ratelimit-requests-remaining` | Requests left |

## Build from source

Requires macOS 13+ and Xcode 15+.

```bash
# Clone
git clone https://github.com/Lcharvol/Claude-God.git
cd Claude-God

# Install xcodegen (one time)
brew install xcodegen

# Generate Xcode project and build
xcodegen generate
xcodebuild -project ClaudeGod.xcodeproj -scheme ClaudeGod -configuration Release build
```

Or open `ClaudeGod.xcodeproj` in Xcode and press `Cmd + R`.

## Project structure

```
Claude-God/
├── Sources/
│   ├── ClaudeUsageApp.swift       # App entry point, MenuBarExtra setup
│   ├── UsageManager.swift         # API calls, data management, state
│   └── MenuBarView.swift          # UI: popover with usage bars and controls
├── docs/
│   └── index.html                 # Landing page (GitHub Pages)
├── .github/
│   └── workflows/
│       └── build.yml              # CI: auto-build + release on tag push
├── project.yml                    # Xcodegen spec (generates .xcodeproj)
└── README.md
```

**Zero external dependencies.** Only Foundation, SwiftUI, and Combine.

## Releasing a new version

Push a git tag and GitHub Actions builds the `.dmg` automatically:

```bash
git tag v1.0.0
git push origin v1.0.0
```

A new GitHub Release with the `.dmg` attached will be created within minutes.

## Landing page

The `docs/` folder contains a static landing page. To enable it:

1. Go to your repo **Settings** → **Pages**
2. Set source to **Deploy from a branch**
3. Branch: `main`, folder: `/docs`
4. Your site will be live at `https://lcharvol.github.io/Claude-God/`

## Roadmap

- [ ] Auto-refresh on a configurable interval
- [ ] macOS notification when usage drops below a threshold
- [ ] Store API key in Keychain instead of UserDefaults
- [ ] Launch at login support
- [ ] Track multiple models (different rate limits per model)

## License

MIT
