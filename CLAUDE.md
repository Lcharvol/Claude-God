# Claude God — Development Guidelines

## Architecture

- **Language**: Swift 5.9, SwiftUI, macOS 13+
- **Build**: Xcodegen (`project.yml` → `xcodegen generate`)
- **Targets**: `ClaudeGod` (main app) + `ClaudeGodWidget` (WidgetKit extension)

## Code Style

### Functional Programming

Favor the functional paradigm as much as possible:

- **Pure functions** over methods with side effects. Extract logic into static functions that take inputs and return outputs.
- **Immutable values** (`let`) by default. Only use `var` when mutation is strictly necessary.
- **`map`, `filter`, `reduce`, `compactMap`** over `for` loops with mutation. Prefer declarative transformations.
- **Value types** (`struct`, `enum`) over reference types (`class`). Classes only for `ObservableObject` and system interop.
- **No force unwraps** (`!`). Use `guard let`, `if let`, `??`, or `Optional.map`.
- **Avoid mutable shared state**. Pass data explicitly rather than relying on singletons or global state.
- **Small, composable functions**. Each function does one thing. Compose them with pipelines.

```swift
// Prefer
let totalCost = sessions.filter { $0.date >= since }.map(\.cost).reduce(0, +)

// Avoid
var totalCost = 0.0
for session in sessions {
    if session.date >= since {
        totalCost += session.cost
    }
}
```

### Error Handling

- Never silently swallow errors. At minimum, `print("[ClaudeGod] ...")` with context.
- Use `Result` or typed errors for functions that can fail — not just returning `nil`.
- Validate at boundaries (API responses, file I/O, user input), trust internal code.
- Degrade gracefully: show cached data when network fails, show placeholders when data is missing.

### Naming & Clarity

- Functions describe what they return, not what they do: `filteredSessions(since:)` not `filterSessions(since:)`.
- Booleans read as assertions: `isAuthenticated`, `hasExpired`, `needsRefresh`.
- No abbreviations except universally known ones (`URL`, `ID`, `JSON`).
- Constants over magic numbers. Extract hardcoded values to named `static let`.

### Concurrency & Thread Safety

- All UI state mutation on `DispatchQueue.main`.
- Heavy work (JSONL parsing, network) on background queues via `DispatchQueue.global(qos:)`.
- Never mutate `@Published` properties from background threads.
- Use `DispatchWorkItem` with cancellation for debounced work (avoid stale results).
- Avoid race conditions: don't use bare `Bool` flags for synchronization across async boundaries.

### Performance

- JSONL files can be 100MB+. Use `enumerateLines` for streaming, never load full content for line-by-line parsing when avoidable.
- Set file size limits to avoid memory exhaustion.
- Skip files early (modification date, size) before reading content.
- Cache computed results. Don't recompute aggregations on every SwiftUI render — move to the model layer.

### Testing Mindset

- Keep parsing logic in pure static functions (easy to test in isolation).
- Separate data transformation from side effects (network, notifications, persistence).
- One responsibility per function. If a function parses AND notifies AND persists, split it.

### SwiftUI

- Extract views into small, focused components.
- Use computed properties for derived state.
- Keep `@Published` properties minimal — derive what you can.
- Prefer `@ViewBuilder` functions over `AnyView` type erasure.
- Batch state mutations to avoid unnecessary view recomputations.

### Git & Releases

- Commit messages: imperative mood, explain the "why" not the "what".
- Version in `project.yml` (`MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` for both targets), Homebrew cask, and `CHANGELOG.md` must stay in sync.
- Tag releases as `v{version}` (e.g., `v2.9.0`).

#### Release checklist

When asked to release, follow these steps in order:

1. **Bump version** in `project.yml` — update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for both `ClaudeGod` and `ClaudeGodWidget` targets.
2. **Build** to verify compilation: `xcodegen generate && xcodebuild -scheme ClaudeGod -configuration Debug build`.
3. **Commit & push** to `main`.
4. **Tag & push tag**: `git tag v{version} && git push origin v{version}`. GitHub Actions will build the `.dmg` automatically.
5. **Wait for the release** to appear: `gh release view v{version} --repo Lcharvol/Claude-God`.
6. **Download the DMG and compute SHA256**: `curl -sL https://github.com/Lcharvol/Claude-God/releases/download/v{version}/ClaudeGod.dmg -o /tmp/ClaudeGod.dmg && shasum -a 256 /tmp/ClaudeGod.dmg`.
7. **Update the Homebrew tap** at `/tmp/homebrew-tap/Casks/claude-god.rb` — set the new `version` and `sha256`.
8. **Commit & push the tap**: `cd /tmp/homebrew-tap && git add Casks/claude-god.rb && git commit -m "Update claude-god to v{version}" && git push origin main`.

> **Important**: The SHA256 from a local build will NOT match the GitHub-served DMG (GitHub re-processes uploaded assets). Always compute the SHA from the downloaded release DMG, not from a local build.

## Project Structure

```
Sources/
  ClaudeUsageApp.swift    — Entry point, MenuBarExtra
  UsageManager.swift      — State management, API calls, timers
  AuthManager.swift       — OAuth credentials, token refresh
  SessionAnalyzer.swift   — JSONL parsing, cost calculation, timeline
  MenuBarView.swift       — All UI views and components
  HotkeyManager.swift     — Global ⌥⌘C hotkey (Carbon API)
  AppShortcuts.swift      — Shortcuts.app intents
  UpdateChecker.swift     — GitHub release checker
Widget/
  ClaudeGodWidget.swift   — WidgetKit desktop widget
```

## Build & Run

```bash
xcodegen generate
xcodebuild -scheme ClaudeGod -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeGod-*/Build/Products/Release/Claude\ God.app /Applications/
```
