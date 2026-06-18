# Release Process

This document tracks the release flow for NotchFlow maintainers.

## Current Release

- Version: `v0.1.2`
- Date: 2026-06-18
- Status: Patch release for the screen health card
- Distribution: GitHub Release `.zip`
- Signing: local signing only, not notarized
- Website: https://aicode-nexus.github.io/NotchFlow/

## Release Checklist

1. Confirm `CFBundleShortVersionString`, `MARKETING_VERSION`, and the tag version match.
2. Regenerate app icons and website images.
3. Run `swift test`.
4. Run a Release Xcode build.
5. Package `NotchFlow.app` as a zip.
6. Review `README.md`, `CHANGELOG.md`, and the GitHub Pages site.
7. Commit release materials.
8. Push `main`.
9. Enable GitHub Pages from `main` / `docs`.
10. Set the repository About URL to the Pages URL.
11. Create the signed Git tag and GitHub Release.

## Commands

```bash
swift scripts/generate_release_assets.swift
swift test
xcodebuild -project NotchFlow.xcodeproj -scheme NotchFlow -configuration Release -derivedDataPath .build/xcode-derived build
ditto -c -k --keepParent .build/xcode-derived/Build/Products/Release/NotchFlow.app dist/NotchFlow-v0.1.2-macOS.zip
gh release create v0.1.2 dist/NotchFlow-v0.1.2-macOS.zip --title "NotchFlow v0.1.2" --notes-file RELEASE_NOTES.md
```

## Notarization Gap

`v0.1.2` is intentionally published as a developer preview without Developer ID notarization. A future production-quality release should add Developer ID signing, notarization, a DMG or PKG installer, and automated release builds.
