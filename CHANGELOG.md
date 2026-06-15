# Changelog

All notable changes to NotchFlow are documented here.

## [0.1.0] - 2026-06-15

### Added

- First public macOS preview release.
- Notch-style menu bar app with hover expansion, click pinning, auto hide, and global hotkey support.
- Now Playing panel with playback controls and Music fallback behavior.
- Weather and device battery presentation with compact fallback behavior.
- Screen health tracking with active time, continuous duration, score, and break reminders.
- Clipboard history, quick launch shortcuts, script shortcuts, and wallpaper refresh controls.
- AI token usage reader for local Claude/Codex usage logs.
- Experimental charge limit service with bundled SMC helper.
- Settings window for modules, appearance, launch at login, text size, intervals, and permissions.
- GitHub Pages landing page, release README, and reusable NotchFlow logo/app icon assets.

### Changed

- Repositioned the public README from prototype notes to release-ready product documentation.
- Documented install, build, testing, and release limitations for the first public build.

### Known Limitations

- The release asset is locally signed but not notarized with Apple Developer ID.
- Weather, automation, and launch-at-login behavior depend on macOS permissions.
- Charge limit support remains experimental because SMC behavior differs across hardware.

[0.1.0]: https://github.com/AICode-Nexus/NotchFlow/releases/tag/v0.1.0
