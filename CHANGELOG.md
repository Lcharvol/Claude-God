# Changelog

All notable changes to this project will be documented in this file.

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
