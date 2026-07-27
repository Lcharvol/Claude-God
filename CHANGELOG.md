# Changelog

All notable changes to this project will be documented in this file.

## [2.24.3] - 2026-07-27

### Fixed
- **Transparent phantom window when changing text size** — switching between S / M / L / XL left a visible transparent halo around the popover because `WindowTopAnchor` only resized the underlying `NSPanel`'s height, not its width. The SwiftUI content resized to match the new `textScale`, but the `NSPanel` kept its previous width, so shrinking left extra empty backing on one side and growing pushed content beyond the window edge. The anchor now tracks width too and keeps the top-right corner (`maxX`, `maxY`) fixed, so the popover stays anchored under its status item and expands leftward — matching macOS's natural popover behavior instead of drifting off the right edge of the display

## [2.24.2] - 2026-07-27

### Fixed
- **"Sign In" button did nothing, no error shown** — on a fresh install without the `claude` CLI on `PATH`, clicking Sign In in the Settings pane flashed "Signing in..." for ~200ms then reverted to "Sign In" with no visible feedback. `launchAutoReconnect` was setting the correct error message ("Claude CLI not found. Install it with `npm i -g @anthropic-ai/claude-code`…"), but the Settings Authentication card only rendered the button — it never displayed `errorMessage`. Only the Usage-tab error banner did, and fresh-install users are routed straight to Settings (`!isAuthenticated` forces `settingsView`), so they could never see it. The Authentication card now shows the error under the Sign In button whenever it's set and no embedded terminal is active

## [2.24.1] - 2026-07-27

### Fixed
- **Intel Mac support restored** — the release DMG is now a universal binary (arm64 + x86_64) that runs on both Apple Silicon and Intel Macs. The GitHub Actions runner is Apple Silicon (`macos-15`) and `xcodebuild` was building only the runner's active arch, so every release since the CI move produced an arm64-only binary that Intel users couldn't launch. Added `ARCHS="arm64 x86_64"` + `ONLY_ACTIVE_ARCH=NO` to the workflow; no source changes needed (pure SwiftUI + WidgetKit, zero native deps) ([#34](https://github.com/Lcharvol/Claude-God/issues/34), thanks @kelvincht for the diagnosis and the exact fix)

## [2.24.0] - 2026-07-27

### Added
- **Adjustable popover text size (S / M / L / XL)** — a new preset picker in Settings resizes every font in the popover (Usage, Analytics, Timeline, ROI, Extensions, Settings). Implemented as a `textScale` environment value plus a `.shFont(_:weight:design:)` view modifier that multiplies each requested point size by the user's preference, so text is laid out and rasterized at its real size (no `.scaleEffect` blur). Popover width scales with the multiplier so bigger type doesn't wrap. Menu bar rendering is untouched; default `M` (1.0) leaves existing users unchanged ([#33](https://github.com/Lcharvol/Claude-God/issues/33), [#39](https://github.com/Lcharvol/Claude-God/pull/39), thanks @nairdaleo)
- **Model-scoped weekly quotas surfaced in the usage list** — model-specific weekly limits (currently the **Fable** quota on Max plans and above) only appear in the OAuth response's `limits` array, not as a top-level bucket. Each `weekly_scoped` entry is now decoded and rendered as `"Weekly (<name>)"` (e.g. "Weekly (Fable)"), lining up with the existing "Weekly (all)" row. Scoped quotas are appended after the legacy buckets so the menu bar `W %` first-match lookup still resolves to "Weekly (all)"; downstream code (notifications, alert rules, rings, widget) picks them up generically. Accounts without scoped limits see no difference ([#36](https://github.com/Lcharvol/Claude-God/pull/36), thanks @pieropalevsky)

### Fixed
- **Permanent "Session expired" that no sign-in could clear** — two independent bugs combined into an unrecoverable state:
  - `loadCredentials()` / `reloadCredentials()` returned the contents of `~/.claude/.credentials.json` whenever it held a non-empty `accessToken`, without ever checking expiry. Newer Claude Code versions refresh into the Keychain and leave the file stale, so the app pinned itself to a dead token while a valid one sat in the Keychain unread — and the expired-credential poller re-read the same dead file every 10s. Both entry points now delegate to a single `resolveCredentials(completion:)`: the file is used only while its token is still valid (fast path, no Keychain round-trip in the common case), otherwise the best Keychain entry is compared against the file and whichever `expiresAt` is later wins, then the `CLAUDE_CODE_OAUTH_TOKEN` env var as a final fallback. A read that finds nothing no longer clears `isAuthenticated` when a token was already loaded, so a transient failure can't sign the user out.
  - The embedded sign-in terminal ran `claude auth login` in a PTY but had no stdin write path, so the "paste your authorization code" prompt was unanswerable and every in-app sign-in timed out. `TerminalSession.send(_:)` now performs a line-buffered write to the master FD (handling partial writes), and `EmbeddedTerminalView` shows a monospaced input row while the session is running.
  
  ([#37](https://github.com/Lcharvol/Claude-God/issues/37), [#38](https://github.com/Lcharvol/Claude-God/pull/38))

## [2.23.4] - 2026-06-15

### Fixed
- **Repeated "Claude God wants to use your confidential information stored in 'Claude Code-credentials-XXXXXXXX'" prompt** — newer Claude Code versions write credentials under a suffixed service name (e.g. `Claude Code-credentials-88d13be2`), and the per-entry data fetch in `loadBestKeychainEntryWithPrefix` was using `SecItemCopyMatching + kSecReturnData`. That call goes through the Security framework, which triggers the macOS keychain access dialog on every read — producing a dialog loop where "Allow" only suppresses one cycle. The fetch now reuses the existing `readKeychainViaSecurityCLI(service:account:)` helper (`/usr/bin/security find-generic-password` with the exact service name discovered from the non-prompting list query), which bypasses the Security-framework dialog entirely ([#30](https://github.com/Lcharvol/Claude-God/issues/30), [#31](https://github.com/Lcharvol/Claude-God/pull/31), thanks @nairdaleo)

## [2.23.3] - 2026-06-08

### Fixed
- **No more "Claude God wants to access the keychain" prompt for the common case** — v2.23.2's Keychain scan used the Security framework directly, which triggers macOS's keychain access dialog the first time an ad-hoc-signed app reads an item it didn't create. `loadFromKeychain` now tries `/usr/bin/security find-generic-password -s "Claude Code-credentials" -a $USER` as a second fast path before calling `SecItemCopyMatching` — the shelled-out binary has its own trusted keychain access, so single-user installs (the vast majority) resolve cleanly without any prompt. The Security-framework scan only runs as a last resort for unusual multi-account / suffixed-entry layouts

## [2.23.2] - 2026-06-08

### Fixed
- **PR #27 Keychain fallback actually works now** — the multi-entry scan in `loadBestKeychainEntryWithPrefix` called `SecItemCopyMatching` with `kSecReturnAttributes + kSecReturnData + kSecMatchLimitAll`. On the legacy file-based login keychain that combination returns `errSecParam (-50)`, so the function returned nil before reading any items, leaving users "Not connected" even when valid OAuth credentials existed in the Keychain. The scan now lists with refs+attributes, then fetches each item's data with a per-item query, so multi-entry keychains (Claude Code stores `account=unknown` and `account=<user>` side-by-side) resolve to the entry with a real `claudeAiOauth.accessToken`

## [2.23.1] - 2026-06-08

### Fixed
- **Embedded `claude auth login` no longer crashes the app** — the PTY slave file descriptor was being closed twice (once explicitly after fork, then again when the `FileHandle` was deallocated with `closeOnDealloc: true`). After the first `close()` recycled the FD number, the OS reused it for a guarded keychain/socket FD, so the handle's dealloc triggered `EXC_GUARD` on whatever now owned that slot. Switching the slave handle to `closeOnDealloc: false` removes the double-close ([#26](https://github.com/Lcharvol/Claude-God/issues/26), [#27](https://github.com/Lcharvol/Claude-God/pull/27), thanks @nairdaleo)
- **Credentials detected when only per-project keychain entries exist** — newer Claude Code versions write credentials to suffixed Keychain entries like `"Claude Code-credentials/path/to/project"` and may leave the base `"Claude Code-credentials"` entry stale or absent. `AuthManager.loadFromKeychain()` now falls back to a Security-framework scan that picks the best valid entry across all `"Claude Code-credentials*"` items when the base entry is missing or expired, so users who appeared "Not connected" right after signing in are picked up correctly
- **Popover only grows downward when resizing** — in Release/Homebrew builds SwiftUI was resizing the `MenuBarExtra` window from its center, causing the popover to expand from both top and bottom and detach visually from the status bar item. A new `WindowTopAnchor` pins `maxY` (the top edge) so the window stays anchored to the menu bar while the bottom edge follows the drag

## [2.23.0] - 2026-06-01

### Added
- **Extra Usage surfaced as a first-class quota across the app** — enterprise/work accounts with a dollar-only budget (no token quotas) previously saw "—" in every menu bar percentage mode. Extra Usage spend/limit is now rendered as a % everywhere token quotas are: the menu bar icon color reacts to high spend (warning/critical), the "All" mode appends `E X%` alongside token percentages, Extra Usage is a selectable ring in Icon+ Rings mode, and standard "Alert when usage is high" plus custom alert rules now fire for it too. The popover's Extra Usage card also gains a color-coded progress bar and percentage when a monthly limit is set; unlimited plans keep the On/Off badge ([#25](https://github.com/Lcharvol/Claude-God/pull/25), thanks @ecoffey)

## [2.22.2] - 2026-05-26

### Changed
- **Peak hours window updated to Anthropic's new 5am–11am PT band** — reflects the policy change announced 2026-03-26 where 5-hour session limits burn faster during weekdays 5am–11am Pacific (1pm–7pm GMT) due to overlapping US-morning, European-afternoon, and Asia-evening demand. The previous 7am–5pm PT window was Claude God's original guess at "US business hours" and no longer matched Anthropic's actual throttling band ([#24](https://github.com/Lcharvol/Claude-God/pull/24), thanks @pieropalevsky)

### Refactored
- **Peak-hours tooltip drift eliminated** — `MenuBarView` tooltips now derive from a single `UsageManager.peakHoursDescription` computed from `peakStartHour` / `peakEndHour` constants, so future window changes touch one place instead of three. Doc-comment also rewritten to explain *why* the window is what it is (Anthropic global throttling, not US business hours)

## [2.22.1] - 2026-05-26

### Fixed
- **OAuth token self-refresh returning HTTP 400** — `selfRefreshToken` now sends `application/x-www-form-urlencoded` with proper percent-encoding (RFC 6749 §6) instead of `application/json`, so the platform token endpoint accepts the refresh grant ([#21](https://github.com/Lcharvol/Claude-God/issues/21), [#22](https://github.com/Lcharvol/Claude-God/pull/22))
- **`claude` binary not found with nvm/fnm/volta/pnpm installs** — `launchAutoReconnect()` now falls back to `$SHELL -l -c "which claude"` when none of the hardcoded paths match, and adds the fnm default-alias path as an extra candidate. Error message also points users to `npm i -g @anthropic-ai/claude-code` when the CLI is genuinely missing
- **No recovery after manual `claude auth login`** — added a 10s background poller (`startExpiredCredentialPolling`) that reloads credentials from file *and* Keychain when the token is expired but no embedded reconnect flow is running. macOS Keychain-only credential writes are now picked up automatically without the user clicking Sign In

## [2.22.0] - 2026-05-04

### Added
- **Rings menu bar mode** — Apple Watch-style concentric activity rings showing up to 3 quotas at a glance, with a small "C" in the center. Configurable in Settings (pick which quotas to display) with a live legend preview. A virtual "Timer" ring option fills as the 5h session window progresses toward reset. Uses `NSImage` + `NSBezierPath` for full-color rendering in the menu bar (SwiftUI Canvas/Circle render as templates in `MenuBarExtra` labels), with appearance-aware background tinting for legibility on light menu bars ([#20](https://github.com/Lcharvol/Claude-God/pull/20))

## [2.21.1] - 2026-05-04

### Fixed
- **Energy consumption** — drastically reduced background CPU activity ([#14](https://github.com/Lcharvol/Claude-God/issues/14)): removed `disableAppNap()` (was blocking macOS's main background-app energy optimization), countdown timer is now adaptive (60s when remaining > 1h, 1s only in the final hour where seconds are visible), active-session check slowed from 15s to 60s, and the 30-day JSONL stats scan is deferred to popover-open instead of running on every auto-refresh tick
- **Widget never registered** — added the missing `NSExtensionPointIdentifier` in `ClaudeGodWidget.appex/Info.plist` so macOS now recognizes the bundle as a WidgetKit extension and lists it in the widget gallery ([#13](https://github.com/Lcharvol/Claude-God/issues/13))
- **Resizable popover actually works** — replaced the broken `WindowResizer` (its `view.window` guard exited silently before SwiftUI attached the host view, so `.resizable` was never inserted) with a SwiftUI `ResizeHandle`: visible grip just above the bottom toolbar, vertical-resize cursor on hover, drag to grow / shrink the popover

## [2.21.0] - 2026-05-04

### Added
- **Session+Week menu bar mode** — new display option shows session %, time-to-reset, and weekly % at a glance (`15% · 2h31m | W 31%`) ([#15](https://github.com/Lcharvol/Claude-God/issues/15))
- **Resizable window** — drag the bottom edge to set the panel height; persists across launches via `UserDefaults`
- **Extra usage balance card** — new card in the usage view shows extra credits used and monthly limit (API returns cents, displayed as dollars)
- **Claude Design quota row** — `seven_day_omelette` API field now parsed and rendered alongside Sonnet / Opus / Haiku
- **Sign In button + auto-reconnect** — when the OAuth token expires, the error view and Settings show a "Sign In" button that opens Terminal with `claude auth login`. New opt-in toggle "Auto-reconnect when session expires" in Settings
- **PTY-embedded `claude auth login`** — auth runs in a real PTY inside the popover for proper TTY behavior during the OAuth flow
- **Silent OAuth self-refresh** — keeps the app online without user interaction while the refresh token is valid
- **Debug: copy raw API response** — button in the About section copies the last raw OAuth usage JSON to the clipboard

### Fixed
- Usage tab no longer flickers when OAuth token is expired ([#7](https://github.com/Lcharvol/Claude-God/pull/7))
- Long reset times now displayed as days/hours instead of raw hours
- Window can shrink below content height for proper scrolling
- Keychain is polled every 5s after `claude auth login` instead of relying solely on the file watcher
- `claude auth login` opens Terminal instead of being spawned headless

## [2.20.4] - 2026-04-13

### Fixed
- Cancelled fetches now properly clear loading state (was stuck forever if cancelled at wrong time)
- All credential reload callbacks use `finishLoading()` consistently — no more manual `isLoading = false` that could desync
- Removed redundant nested `DispatchQueue.main.async` in 401/403 and 429 token refresh callbacks
- Rate limit backoff counter resets when cooldown expires naturally (was only on 200 or manual retry, causing stuck 10min backoff)
- Added 10s timeout safety on all credential reload callbacks — prevents permanent stuck state if callback never fires
- Removed unused `fetchID` variable in fetch setup

## [2.20.3] - 2026-04-13

### Fixed
- Respect server `Retry-After` header on 429 instead of capping to 60s — stops hammering the API during long rate limits
- Progressive backoff when no `Retry-After` header: 30s → 2min → 10min → 30min → 1h → 2h cap
- Pre-flight token expiry check avoids doomed API calls with expired tokens
- Credential reload now falls back to Keychain when `.credentials.json` is missing (macOS Claude Code stores credentials in Keychain only)
- Cap server-provided `Retry-After` at 2h to protect against malformed headers
- Updated all user-facing messages from `claude login` to `claude auth login`

## [2.20.2] - 2026-04-08

### Fixed
- App no longer gets stuck on "Rate limited" screen after `claude login` (fixes #5)
- Rate limit error now shows "Retry" button instead of incorrectly showing "Settings"
- Credential changes (e.g. after `claude login`) now trigger auto-refresh even when an error is displayed
- Auto-refresh retries after 60s instead of giving up permanently when rate limited with no cached data

## [2.20.1] - 2026-04-02

### Fixed
- Refresh no longer gets stuck or spins forever — fetch requests are now cancellable with stale response detection
- All retry paths use `[weak self]` to prevent retain cycles and parallel fetch races
- Centralized `finishLoading()` guarantees `isLoading` is always reset (no more missed code paths)
- Safety timeout reduced to 20s and now cancels the in-flight request
- Wake observer cancels stale fetches before refreshing

## [2.20.0] - 2026-04-02

### Added
- Peak / Off-peak indicator in usage view — shows whether you're in peak hours (Mon–Fri 7am–5pm PT) with countdown to next transition

### Fixed
- Menu bar timer now shows session reset instead of weekly reset when usage is at 0%
- Reset timer displays days/hours for long countdowns (e.g. `3d05h` instead of `77h05m`)

## [2.19.3] - 2026-03-31

### Fixed
- Auto-refresh was off by default for new users (UserDefaults returned 0 = "Off" on first launch instead of 2 min)

## [2.19.2] - 2026-03-31

### Fixed
- App no longer stops refreshing after Mac sleep/wake — timers are recreated on wake
- Disabled App Nap so refresh timers are never paused by macOS
- Auto-refresh when opening the popover if data is older than 2 minutes
- `isLoading` stuck state: safety timeout after 30s, reset on wake, and proper handling when access token is nil
- 401/403 token refresh no longer enters infinite retry loop

## [2.19.1] - 2026-03-21

### Fixed
- Manual refresh now always bypasses rate limit cooldown (no more stuck "Rate limited" requiring app restart)
- Rate limit cooldown capped to 60s max
- No error message shown when rate limited with cached data — displays existing quotas silently

## [2.19.0] - 2026-03-19

### Performance
- JSONL parsing: eliminate Data→String→Data roundtrip in 5 functions (saves memory on 100MB+ files)
- SQLite: combine 9 queries into 4 per refresh (stats as single subquery, projects derived from summaries)
- Widget: skip update when quotas unchanged (avoid JSON encode + WidgetCenter reload)
- Keychain: read credentials off main thread to prevent UI freezes on startup

### Added
- "brew upgrade claude-god" copy button in update banner

## [2.18.1] - 2026-03-18

### Fixed
- Delay first API call by 3s on startup to avoid racing with Claude Code
- `reloadCredentials` no longer reads Keychain — only reads file to avoid interfering with Claude Code's keychain access
- Reduces risk of invalidating Claude Code's OAuth session on app launch

## [2.18.0] - 2026-03-17

### Added
- GitHub plugin detail view — 26 MCP tools grouped by category (PRs, Issues, Search, Files, Repos), auth status indicator
- Generic plugin detail views for swift-lsp, code-review, code-simplifier, context7, playwright — features list with icons and descriptions
- Plugin update button — "Update to vX.Y.Z" on installed plugins with available updates (runs `claude plugin update`)
- 9 plugins now have custom detail views in the Extensions tab

### Fixed
- Menu bar icon uses system color (black/white) in normal state for better contrast — green/orange/red only for warnings
- Font sizes increased +1pt on small text (7→8, 8→9, 9→10, 10→11) for readability
- App window slightly wider (380→400px)

## [2.17.1] - 2026-03-16

### Fixed
- Stop refreshing OAuth tokens — reload credentials from disk instead. The single-use refresh token was invalidating Claude Code's copy, forcing repeated `claude login`.

## [2.17.0] - 2026-03-16

### Added
- Superpowers plugin detail view — browse all 14 skills with descriptions, categories, and line counts; view implementation plans with progress bars and design specs
- Frontend Design plugin detail view — design principles reference, aesthetic tones palette, anti-patterns checklist, and link to Anthropic's Frontend Aesthetics Cookbook
- Both plugins now appear as featured cards in the Installed tab with "Open" navigation

## [2.16.1] - 2026-03-16

### Fixed
- Landing page screenshots now display correctly (copied to `docs/images/`)
- Added Extensions tab screenshots to landing page gallery

## [2.16.0] - 2026-03-16

### Added
- Extensions tab — replaces Memory tab with a full plugin marketplace
- Discover sub-tab — browse all available Claude Code plugins sorted by popularity, with search and category filter
- Installed sub-tab — manage installed plugins with enable/disable toggle, uninstall, and update indicators
- Featured plugin cards — plugins with custom UI (claude-mem) shown prominently with icon, description, and clickable card to open detail view
- Plugin installation directly from the app via `claude` CLI (`Process()`)
- Category chips for filtering (Development, Productivity, Database, Design, etc.)
- Install count display (e.g. "324.0K") from marketplace data

### Changed
- Memory tab renamed to Extensions; Memory content now accessible via claude-mem's "Open" detail view in Installed
- Plugin data loaded from local `~/.claude/plugins/` files (no network required)

## [2.15.0] - 2026-03-16

### Fixed
- Memory tab now reads the correct `observations` table from claude-mem (was querying non-existent `memories` table)
- Fixed column mappings to match actual claude-mem schema (`memory_session_id`, `narrative`, `files_read`, `files_modified`)

### Added
- Memory activity timeline — bar chart of observations over the last 30 days with summary stats
- Project summaries view — aggregated facts, concepts, and files per project
- Export memories as Markdown — copy all or per-project to clipboard
- Copy/delete individual observations via context menu on each memory row
- Clickable file paths — open referenced files or project folders in Finder
- Type badge on each observation row
- Narrative display in memory rows

## [2.14.0] - 2026-03-16

### Added
- Memory tab — integrates claude-mem plugin data (SQLite read-only) to browse Claude's persistent memories
- Memory search and project filter
- Stats cards showing total memories, sessions, projects, and weekly count
- Install guide encart when claude-mem is not installed
- Changelog section on landing page and README
- Changelog nav link on landing page

### Changed
- Release checklist in CLAUDE.md now includes updating CHANGELOG.md, README, and landing page changelog

## [2.13.1] - 2026-03-16

### Fixed
- OAuth token refresh no longer persists tokens to `~/.claude/.credentials.json` — prevents daily 401 errors by keeping refreshed tokens in-memory only (Claude Code manages credentials)

## [2.13.0] - 2026-03-16

### Performance
- Single JSON decode per JSONL line via `JSONLContent` Decodable enum (eliminates JSONSerialization + JSONDecoder double-parse)
- Direct `Data` line splitting in `enumerateJSONLines` — avoids Data→String→Data roundtrip
- Single-pass file traversal with `analyzeWithSessions()` combining stats + recent sessions
- `resourceValues(forKeys:)` replaces `attributesOfItem(atPath:)` for file metadata (fewer syscalls)
- `.utility` QoS for background stat computation instead of `.userInitiated`
- Binary search + reverse scan for ROI assisted commit matching
- Dedicated `sessionCost(for:)` avoids re-scanning all files for active session cost

### Changed
- Updated README with 4 real screenshots (Usage, Analytics, Timeline, ROI)

## [2.12.0] - 2026-03-14

### Added
- Quality improvements to logging, error handling, forecasting, and exports

## [2.11.0] - 2026-03-13

### Added
- ROI tab — correlates git commits with Claude sessions to show cost per commit
- ROI sparkline with 30-day trend and cost/commit efficiency tracking
- Per-project and per-model ROI breakdown
- GitAnalyzer module for git log parsing and commit data extraction

## [2.10.0] - 2026-03-12

### Added
- Updated Opus and Haiku pricing to March 2026 rates
- Landing page SEO improvements: keywords, FAQ schema, sitemap.xml, robots.txt
- Live download counter and GoatCounter analytics on landing page
- GitHub stars badge promoted on landing page

### Fixed
- Project cost truncation in Analytics tab
- Setup section layout — 3-column grid and shorter brew command
- Mobile responsive layout for landing page
- 429 stale token handling

## [2.9.0] - 2026-03-11

### Fixed
- Token refresh race condition — prevent concurrent refresh requests
- Notification spam on oscillating quotas — added hysteresis (must drop 5-10% to re-arm)
- Reset timer stuck on "now" — auto-refreshes 3s after quota reset
- Multi-account switch flash — keep old data until new quotas arrive
- Menu bar timer overflow — compact format (2h31m instead of 2h 31m 45s)
- Session topic shows "test" — now picks first substantial message (>20 chars)
- Budget field shows $0 — now displays "Not set" placeholder
- CSV export silent failure — button shows "Saved!" or "Failed" feedback
- Duplicate custom alert rules — prevents adding same quota/threshold combo
- Models section layout — aggregate by short name, wider cost column, compact formatting

### Improved
- Active session polling reduced from 10s to 15s
- Stats refresh cancels previous in-flight work on rapid clicks
- Efficiency trend requires 10+ days of data (was 4, too noisy)
- Hotkey failure shown as warning in Settings
- Menu bar icon: warning (70% opacity) vs critical (full) visually distinct
- 429 rate limit auto-retries 3 times instead of showing error immediately
- Unknown model pricing logs a warning instead of silent fallback

## [2.8.0] - 2026-03-11

### Added
- macOS Desktop Widget (WidgetKit) — quota gauges on the desktop with auto-refresh
- Usage heatmap — GitHub-style calendar showing 8 weeks of daily usage intensity
- Live session cost — real-time cost counter and message count for active Claude Code session
- Week-over-week comparison — cost and message delta view (this week vs last week)
- Per-project monthly budget — set $/month per project with progress bars and alert notifications
- Efficiency metrics — cost/message, tokens/session, cache hit rate, and trend indicator
- Shortcuts.app integration — "Get Claude Usage", "Get Claude Cost", "Refresh Claude" actions
- Multi-account support — add/switch/remove Claude credential profiles in Settings
- Custom alert rules — per-quota threshold notifications (e.g. "Opus 7d > 60%")
- Session annotations — star and tag sessions for later reference

## [2.7.0] - 2026-03-11

### Added
- Global keyboard shortcut `⌥⌘C` to toggle the popover from anywhere (Carbon hotkey API)
- Homebrew cask distribution: `brew tap lcharvol/tap && brew install --cask claude-god`

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
