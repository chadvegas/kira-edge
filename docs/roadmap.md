# Kira Edge Roadmap

## Goal

Build a macOS-native iCUE-style widget host for the Corsair XENEON EDGE while
leaving Touchscreen Gestures responsible for touch input.

## Current MVP

- Native SwiftUI macOS app.
- Auto-detects the XENEON display by name or strip-like aspect ratio.
- Moves the dashboard window onto the XENEON panel.
- Edge mode hides window chrome and can pin the dashboard above normal windows.
- Built-in widgets:
  - Clock
  - System CPU, memory, disk, and local IP
  - Power
  - Apps launcher
  - Note
  - Now Playing with artwork, progress, and transport controls through the
    vendored `mediaremote-adapter`

## Next Widgets

- Calendar agenda through EventKit.
- Home Assistant controls.
- Shortcuts launcher.
- Stream Deck style command buttons.
- Weather from a configurable provider.
- BetterDisplay/DDC controls if we decide to keep BetterDisplay installed.

Now Playing is implemented in the current branch. Distribution builds require
both its Swift sources and the checksum-pinned vendor tree; it is not a
best-effort or reduced-build feature.

## Plugin Direction

iCUE widgets are web-oriented. For this app, the safer path is:

1. Built-in Swift widgets for core system controls.
2. A local JSON manifest format for user widgets.
3. A sandboxed WebKit widget runtime for HTML/CSS/JS widgets.
4. A bridge API for limited host actions such as opening apps, running
   shortcuts, and reading approved sensor values.
