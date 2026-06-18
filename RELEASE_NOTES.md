# NotchFlow v0.1.1

NotchFlow v0.1.1 is a patch release for the native macOS notch utility.

## Highlights

- The menu bar dropdown no longer reserves a large blank area when there is no Now Playing title.
- Now Playing titles are trimmed before display, and empty or whitespace-only titles are treated as no content.
- The menu bar dropdown now observes nested media, panel, and wallpaper refresh state directly so labels and disabled states stay current.

## Install

Download `NotchFlow-v0.1.1-macOS.zip`, unzip it, and move `NotchFlow.app` to `/Applications`.

This preview is locally signed but not notarized. On first launch, macOS may require right-clicking the app and choosing **Open**.

## Known Limitations

- Weather, automation, and startup behavior depend on macOS permissions.
- Charge limit controls are experimental and may vary by Mac hardware.
- The app is distributed as a simple zip for this preview; notarized packaging is planned for a later release.
