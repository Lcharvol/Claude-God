# Changelog

All notable changes to this project will be documented in this file.

## [2.6.0] - 2026-03-11

### Added
- Burn rate prediction: estimates when you'll hit quota limit based on current velocity
- Per-project cost breakdown: shows top projects with cost, messages, and session count
- Session history: recent conversations with topic, duration, cost, and model
- Model advisor: smart tips when quota imbalance is detected (e.g. switch to Sonnet)
- Reset notifications: alerts when a quota resets (detects drop from >50% to <10%)
- Active session detection: green pulsing dot when Claude Code is running (checks JSONL file modification)
- Daily budget tracking: set a $/day target with progress bar
- README screenshots: usage and analytics views illustrated at top of README

## [2.5.0] - 2026-03-11

### Added
- File watcher on `~/.claude/.credentials.json` — auto-detects `claude login` and connects without manual retry
- Keyboard shortcuts: `⌘1` Usage tab, `⌘2` Analytics tab
- Accessibility: VoiceOver labels on quota cards, stat cards, reset timer, progress bars
- Native tooltips on daily usage bars (cost, messages, tokens on hover)
- Total row in Models section (tokens + cost)
- Retry button directly in error cards
- Loading spinner on Analytics refresh button

### Changed
- Menu bar icon color now reflects the **worst** quota (highest utilization) instead of always the session quota
- Auto-refresh now also refreshes JSONL analytics stats
- Sparkline chart follows the daily period selector (7d/14d/30d) instead of being hardcoded to 7 days
- Quota cards show relative reset time ("Resets in 2h 31m") instead of absolute time
- High utilization precision: shows one decimal above 95% (e.g. "97.3%"), rounds to 100% above 99.5%
- Countdown hides seconds when timer is not displayed in menu bar (cleaner popover display)
- Notification threshold UX: shows "Alert at 80% used (20% left)" instead of "Remaining < 20%"
- Daily range selection (`dailyRange`) persisted via `@AppStorage` across app launches
- Sparkline fill opacity adapts to dark/light mode
- Stat card values animate with `.contentTransition(.numericText())`
- SparklineView uses `@ViewBuilder` instead of `AnyView` type erasure

### Removed
- Unused `Theme.radiusLg` design token

## [2.4.0] - 2026-03-10

### Added
- Menu bar display modes: Icon only, Session %, Timer, All quotas (configurable in Settings)
- About section with GitHub link and Report Issue button
- Independent refresh button for analytics stats
- Daily period selector: 7d / 14d / 30d segmented picker
- Interactive sparkline with hover tooltip (day label + cost)
- Session count displayed in 30-day stat card
- Empty state in analytics when no JSONL data found
- `⌘R` keyboard shortcut for refresh

### Changed
- Architecture split: extracted `AuthManager` and `UpdateChecker` from `UsageManager`
- Single-pass JSONL analysis with `filtered(since:)` for sub-period derivation (3x → 1x file scan)
- `enumerateLines` for memory-efficient JSONL processing
- Exponential backoff retry (3 attempts) for network errors and 5xx responses
- Multi-threshold notifications: user threshold + 95% emergency, persisted via UserDefaults
- Countdown timer interval adapts to menu bar display mode (1s vs 30s)
- Compact mode shows "Updated" with last refresh time
- `objectWillChange` forwarding from sub-managers via Combine

### Removed
- `KeychainHelper.swift` (unused dead code)

## [2.3.0] - 2025-07-15

### Added
- shadcn/ui-inspired design system with Theme design tokens
- Custom components: `SHCard`, `SHButton`, `SHBadge`, `SHTab`, `SHIconButton`, `SHStatCard`, `SHDivider`, `SHLabel`
- Hover effects on all interactive elements
- Sparkline chart for usage trend visualization

### Changed
- Complete UI redesign with flat, minimal, bordered aesthetic
- Consistent typography and spacing throughout

## [2.2.0] - 2025-06-20

### Added
- Dynamic menu bar icon color based on usage level (green/orange/red)
- Copy stats to clipboard
- Export to CSV
- Compact display mode toggle

### Changed
- Improved cost formatting (3 decimal places for small amounts)

## [2.1.0] - 2025-05-10

### Added
- Session analytics: daily costs, model breakdown, token usage from JSONL files
- Utilization percentage display (used %) matching claude.ai style

### Changed
- Graceful 429 handling: keeps existing data instead of showing error

## [2.0.0] - 2025-04-15

### Added
- App icon (purple gradient C)
- Auto-update checker via GitHub Releases API
- Auto-detect credentials from `~/.claude/.credentials.json`, Keychain, and environment variable

### Changed
- **Breaking**: Migrated from paid API key to OAuth usage endpoint (`/api/oauth/usage`)
- No longer requires manual API key entry — reads Claude Code's own credentials

## [1.1.0] - 2025-03-10

### Added
- Auto-refresh with configurable interval (1, 2, 5, 10 minutes or off)
- API key stored in macOS Keychain (encrypted) instead of UserDefaults
- Automatic migration from UserDefaults for users upgrading from v1.0
- Low usage notifications with configurable threshold
- Auto-refresh when rate limit reset timer expires
- Launch at login toggle (via SMAppService)
- Animated progress bars with gradient fills
- Organized settings UI with labeled sections
- Graceful handling of 429 rate limit responses
- Network entitlements for hardened runtime
- Keychain helper module

### Changed
- Improved popover layout with better spacing and typography
- Monospaced digits for all numeric displays
- Version indicator in bottom bar

## [1.0.0] - 2025-03-10

### Added
- Initial release
- macOS menu bar icon showing token usage percentage
- Token and request usage with color-coded progress bars (green/orange/red)
- Live countdown until rate limit reset
- Manual refresh button
- API key input with SecureField
- Xcodegen-based project generation
- GitHub Actions CI/CD pipeline (build + DMG on tag push)
- Landing page for claudegod.app
