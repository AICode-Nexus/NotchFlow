# NotchFlow

<p align="center">
  <img src="docs/assets/notchflow-logo.png" alt="NotchFlow logo" width="128">
</p>

<p align="center">
  A native macOS notch utility for quick status, media control, launch actions, and lightweight daily context.
</p>

<p align="center">
  <a href="https://aicode-nexus.github.io/NotchFlow/">Website</a>
  ·
  <a href="https://github.com/AICode-Nexus/NotchFlow/releases/latest">Download</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

## What It Does

NotchFlow turns the top center of your Mac screen into a compact, glanceable control surface. It runs as a menu bar app, keeps the Dock clean, and expands from a notch-shaped panel when you hover, click, or use the global shortcut.

The first public release is a developer preview for macOS 14 and newer.

## Highlights

- Notch-style floating panel with hover expansion, click pinning, auto hide, and `Option + Command + Space`.
- Media card with now-playing metadata and playback controls.
- Weather and battery glance module with graceful fallback behavior.
- Screen health module for active time, continuous focus duration, and break reminders.
- Clipboard history, quick launch shortcuts, script shortcuts, and wallpaper refresh tools.
- AI token usage summary for local Claude/Codex usage logs.
- Experimental charge limit controls backed by an included SMC helper.
- Settings window for appearance, text size, modules, refresh intervals, and startup behavior.

## Install

1. Download `NotchFlow-v0.1.0-macOS.zip` from the latest GitHub Release.
2. Unzip it and move `NotchFlow.app` to `/Applications`.
3. If macOS blocks the first launch because the app is not notarized yet, right-click the app and choose **Open**.
4. Grant the requested permissions only for features you enable, such as location, automation, or launch at login.

## Current Release Notes

`v0.1.0` is the first public preview. It is locally signed for distribution testing, but it is not Apple notarized and does not use a Developer ID certificate yet.

Known limitations:

- Some integrations depend on macOS permissions and third-party app availability.
- Weather can fall back when WeatherKit authorization or location access is unavailable.
- Charge limit control is experimental and depends on hardware/SMC behavior.
- Release packaging is a simple `.zip`; notarized DMG packaging is planned for a later release.

See [CHANGELOG.md](CHANGELOG.md) for the complete version history.

## Build From Source

Open the Xcode project:

```bash
open NotchFlow.xcodeproj
```

Run the test suite:

```bash
swift test
```

Build the macOS app:

```bash
xcodebuild -project NotchFlow.xcodeproj -scheme NotchFlow -configuration Release build
```

The Swift Package entry point remains available for quick local iteration:

```bash
swift run
```

## Project Maintenance

Regenerate the Xcode project after adding or removing Swift source files:

```bash
ruby scripts/generate_xcodeproj.rb
```

Regenerate release visual assets and app icons:

```bash
swift scripts/generate_release_assets.swift
```

## Research Notes

Early scope and competitive research remain in:

- `research/competitors.md`
- `research/feature-list.md`
- `research/v1-scope.md`

## License

No open source license has been declared yet. Please contact the repository owner before redistributing modified builds.
