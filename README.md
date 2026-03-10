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

## How it works

The app sends a minimal API request (1 token via Haiku, cost ~$0.00001) and reads the rate limit headers that Anthropic returns with every response:

| Header | What it tells us |
|---|---|
| `anthropic-ratelimit-tokens-limit` | Max tokens per window |
| `anthropic-ratelimit-tokens-remaining` | Tokens left |
| `anthropic-ratelimit-tokens-reset` | When the limit resets |
| `anthropic-ratelimit-requests-limit` | Max requests per window |
| `anthropic-ratelimit-requests-remaining` | Requests left |

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+
- An [Anthropic API key](https://console.anthropic.com/)

## Setup

### 1. Clone

```bash
git clone https://github.com/Lcharvol/Claude-God.git
cd Claude-God
```

### 2. Create the Xcode project

1. Open Xcode → **File** → **New** → **Project**
2. Select **macOS** → **App** → Next
3. Set:
   - Product Name: `ClaudeUsage`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Save anywhere, then **delete** the generated `ContentView.swift` and `ClaudeUsageApp.swift`
5. Drag the 3 files from `ClaudeUsage/` into the Xcode project navigator
   - Check **"Copy items if needed"**
   - Check **"Add to target: ClaudeUsage"**

### 3. Configure as menu bar app

This hides the app from the Dock so it only appears in the menu bar:

1. Click the **project** (blue icon) in Xcode's sidebar
2. Go to the **Info** tab
3. Under **Custom macOS Application Target Properties**, add:
   - Key: `Application is agent (UIElement)`
   - Value: `YES`

### 4. Build & Run

Press `Cmd + R`. The app appears in your menu bar as a `C` icon.

### 5. Enter your API key

Click the icon → paste your Anthropic API key → **Save**. Done.

## Project structure

```
ClaudeUsage/
├── ClaudeUsageApp.swift   # App entry point, MenuBarExtra setup
├── UsageManager.swift     # API calls, data management, state
└── MenuBarView.swift      # UI: popover with usage bars and controls
```

| File | Lines | Role |
|---|---|---|
| `ClaudeUsageApp.swift` | ~25 | Bootstraps the app and creates the menu bar icon |
| `UsageManager.swift` | ~160 | ObservableObject handling API calls and rate limit parsing |
| `MenuBarView.swift` | ~210 | SwiftUI views: settings, usage bars, countdown, buttons |

**Zero external dependencies.** Only Foundation, SwiftUI, and Combine.

## Roadmap

- [ ] Auto-refresh on a configurable interval
- [ ] macOS notification when usage drops below a threshold
- [ ] Store API key in Keychain instead of UserDefaults
- [ ] Launch at login support
- [ ] Track multiple models (different rate limits per model)
- [ ] Xcode project file in the repo for one-click build

## License

MIT
