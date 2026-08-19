# Kira Edge Overview

Last updated: 2026-08-02

## What This Is

Kira Edge is a native macOS SwiftUI app for turning the Corsair
XENEON EDGE into a dedicated widget dashboard. The app treats the Edge as a
small ultrawide second display, sends a fullscreen dashboard window to it, and
keeps a separate settings window on the main Mac display.

The goal is to make the Edge feel more like a Stream Deck plus mini command
center: widgets, web apps, app launchers, system stats, profile presets, and
quick controls, all hosted in a layout designed for the 2560x720 Edge panel.

This app does not currently replace Touchscreen Gestures. Touchscreen Gestures
is still responsible for turning the Edge's touch input into macOS pointer,
tap, and gesture behavior. This app is the visual/runtime layer that lives on
the Edge.

## Installed App

Local installed app:

```bash
/Applications/Kira Edge.app
```

Project source:

```bash
/Users/chadvegas/Projects/xeneon-edge-widgets
```

Build and run from source:

```bash
./script/build_and_run.sh
```

Install the current build into `/Applications`:

```bash
./script/install_app.sh
```

Verify the app launches:

```bash
./script/build_and_run.sh --verify
```

## How It Is Supposed To Be Used

### Normal Daily Flow

1. Launch `Kira Edge.app`.
2. The dashboard window should move to the XENEON EDGE display and enter native
   fullscreen.
3. Use the Edge as the glanceable dashboard.
4. Use the menu bar item named `Kira Edge` or `Command-,` to open Widget Settings
   on the main display.
5. Adjust widgets, presets, appearance, notes, web URLs, and app launchers from
   the settings window.

The dashboard and settings are intentionally separate:

- Dashboard window: lives fullscreen on the Edge.
- Widget Settings window: lives on the main display.
- Menu bar extra: gives quick access without hunting for either window.

### Keyboard Shortcuts

- `Command-Shift-E`: Send dashboard to XENEON Edge.
- `Command-Shift-D`: Toggle Edge mode / show controls.
- `Command-Shift-W`: Toggle widget edit mode.
- `Command-,`: Open Widget Settings.
- `Command-Shift-P`: Pin or unpin the dashboard.

### Menu Bar Controls

The `Kira Edge` menu bar item can:

- Send the dashboard to the Edge.
- Show the dashboard controls window.
- Open Widget Settings.
- Toggle widget editing.
- Pin or unpin the dashboard.
- Reload all web widgets.
- Switch appearance mode.
- Switch presets.
- Quit the app.

### Edge On-Screen Drawer

The dashboard has a small bottom `Menu` tab on the Edge. Tapping it reveals the
temporary drawer/HUD. The drawer auto-hides after a few seconds.

The bottom edge also has a hot zone that accepts tap, drag, swipe, and scroll
events. This is intentionally forgiving because Touchscreen Gestures can turn a
physical swipe into different macOS event types depending on the gesture.

### Widget Settings Tabs

#### Dashboard

The Dashboard tab shows:

- A scaled 2560x720 preview of the actual Edge dashboard.
- Current display status.
- Current action/status text.
- Pinned toggle.
- Preset buttons.
- The note text editor.

Presets replace the current tile layout with a ready-made layout.

#### Widgets

The Widgets tab is where the runtime is configured:

- Gallery: quick-add predefined web, app, and native widgets.
- Add Site: create a custom web tile from a title and URL.
- Add App: create an app tile that can launch and tile an app window.
- Tile list: enable/disable, reorder, change size, change accent, focus, or
  delete widgets.
- Inspector: edit the selected widget, close it, move it left/right, or resize
  it.

Web widgets expose URL, title, and zoom settings.

App widgets expose app name and target zone settings. The current zones are:

- Full
- Left 1/2
- Right 1/2
- Left 1/3
- Middle 1/3
- Right 1/3

#### Display

The Display tab shows:

- Edge appearance mode: Dark, Light, or System.
- Detected display summaries.
- Send and Controls buttons.

Appearance mode is scoped to the Edge dashboard. It should not force the
settings window into an unreadable theme.

## Current Widget Types

### Clock

Shows the current time and date. The clock updates every second through the
shared dashboard timer.

### System

Shows CPU, memory, disk, and local IP. The system snapshot refreshes every few
seconds.

### Power

Shows Mac battery percentage and charging state when available.

### Launcher

Shows configured app launcher buttons. The default launchers are Finder, Music,
Safari, and Codex. The Music shortcut opens Spotify and swaps that Apps tile to
Now Playing; the Apps button on the player restores the launcher grid.

Launching from the Edge opens the app on the main display so the Edge dashboard
does not get buried behind the launched app.

### Note

Shows the persisted note text from the Dashboard tab.

### Web

Embeds a website or web app inside a tile using `WKWebView`. Examples include
YouTube, Google, ChatGPT, GitHub, Calendar, Home Assistant, Plex, Spotify, and
weather pages.

Web tiles support:

- URL configuration.
- Title configuration.
- Zoom control.
- Desktop user agent.
- Reload tokens for manual refresh.
- Focusable keyboard input once the tile is clicked/tapped.

### Now Playing

Shows system-wide playback metadata, artwork, progress, and transport controls.
The app reads and controls playback through the bundled
`mediaremote-adapter` helper. The helper is launched by `/usr/bin/perl` because
recent macOS releases restrict direct MediaRemote access from ordinary app
processes.

### Apps

The Apps launcher opens named macOS applications through `NSWorkspace`. It does
not tile or control another app's windows and does not require Accessibility or
Automation permission.

## Current Presets

The app has six built-in dashboard presets:

- Command: daily controls, launchers, note, system pulse, and a web tile.
- Media: YouTube, Plex, power, and launchers.
- Work: ChatGPT, Calendar, Finder, and system status.
- Streaming: YouTube Studio, Live Chat, Ecamm, power, and launchers.
- AI Ops: ChatGPT, GitHub, Codex, system status, and notes.
- Home: Home Assistant, Weather, Calendar, clock, and launchers.

Applying a preset replaces the active tile list and persists it to the local
profile.

## What Makes It Work

### App Structure

The app is a Swift Package Manager macOS GUI app.

Important paths:

- `Package.swift`: SwiftPM package definition.
- `Sources/XeneonEdgeWidgets/App/XeneonEdgeWidgetsApp.swift`: app entry point,
  scenes, command menu, menu bar item, settings window.
- `Sources/XeneonEdgeWidgets/Stores/DashboardStore.swift`: central app state,
  persistence, window placement, presets, widget operations.
- `Sources/XeneonEdgeWidgets/Models/WidgetModels.swift`: widget, preset,
  appearance, launcher, app zone, and profile models.
- `Sources/XeneonEdgeWidgets/Models/WidgetCatalog.swift`: predefined widget
  gallery.
- `Sources/XeneonEdgeWidgets/Views/`: SwiftUI views for dashboard, settings,
  editor, display panel, menu bar, and widgets.
- `Sources/XeneonEdgeWidgets/Services/`: display detection, system stats,
  launch, calendar, weather, and Now Playing services.
- `Sources/XeneonEdgeWidgets/Support/`: AppKit/WebKit bridges, theme, window
  accessor, formatters, and touch hot zone.
- `Tests/XeneonEdgeWidgetsTests/`: Swift Testing coverage.
- `script/build_and_run.sh`: build and launch helper.
- `script/install_app.sh`: local installer.

### Shared Store

`DashboardStore` is the center of the app. It is an `@Observable` main-actor
object shared by:

- The Edge dashboard window.
- The Widget Settings window.
- The menu bar extra.
- The command menu.

It owns:

- The active tile list.
- The selected preset.
- The selected widget.
- Focused-widget mode.
- Edit mode.
- Pin state.
- Note text.
- Appearance mode.
- System stats.
- Screen/action status.
- Dashboard and settings window references.

### Persistence

The current profile is encoded as JSON and stored in `UserDefaults` under:

```text
dashboardProfile.v2
```

The persisted profile contains:

- Note text.
- Pin state.
- Tiles.
- Launchers.
- Selected preset.
- Appearance mode.

Resetting the profile restores the default command layout and launchers.

### Display Detection

`ScreenResolver` finds the XENEON display by:

1. Looking for an `NSScreen.localizedName` containing `XENEON`.
2. Falling back to a strip-like aspect ratio, currently width/height above 3.0,
   width at least 1800, and height at most 900.

It also finds the primary work display so settings and launched apps can open
on the main monitor instead of behind the Edge dashboard.

### Dashboard Window Placement

The dashboard window is moved to the XENEON screen and then put into native
macOS fullscreen. This hides the menu bar and window chrome on the Edge.

The app has extra guards around fullscreen style changes because macOS can
crash if a fullscreen `NSWindow` has its style mask mutated at the wrong time.

### Settings Window Placement

Widget Settings is its own SwiftUI `Window` scene. When opened, it is centered
on the primary non-XENEON display. This is why settings should appear on the
main monitor while the dashboard remains on the Edge.

### Web Runtime

Web widgets are powered by `WKWebView` through `WebTileWebView`.

The app uses:

- A default website data store, so normal WebKit cookies/session behavior can
  work.
- JavaScript-enabled pages.
- A desktop Safari-style user agent by default.
- Page zoom per widget.
- A custom `FocusableWKWebView` so clicks/taps make the tile keyboard-focusable.
- Small CSS injection to contain overscroll and keep video elements inside the
  tile.

### App Launching

Launcher buttons call `LauncherService` and `NSWorkspace`.

The app opens the selected application without injecting input or moving its
windows. Touchscreen Gestures remains a separate component for converting Edge
touches into macOS pointer input.

### System Stats

`SystemStatsReader` samples:

- CPU from `ps` output.
- Memory from `vm_stat`.
- Disk usage from filesystem resource values.
- Battery from IOKit power sources.
- Local IP from `ipconfig getifaddr` on common interfaces.

Stats refresh every three seconds.

### Touch And Drawer Handling

The drawer uses both SwiftUI gestures and an AppKit bridge:

- SwiftUI `DragGesture` handles obvious bottom-edge swipes.
- `EdgeDrawerHotZone` is an `NSViewRepresentable` that accepts mouse, drag,
  scroll, and swipe events from the bottom strip.
- The visible `Menu` tab is the reliable fallback when touch gesture translation
  is inconsistent.

### Theme System

`EdgeTheme` contains dashboard colors. It uses dynamic AppKit colors so the Edge
dashboard can render in dark, light, or system mode.

The important detail: the dashboard applies its appearance via a local
`colorScheme` environment value. It does not use a window-level preferred color
scheme, because that can leak into the settings window and make settings text
unreadable.

## Permissions

Kira Edge does not require Accessibility, Automation, Input Monitoring, or
Screen Recording. Bluetooth is optional for accessory battery details, and
Google Calendar is optional OAuth. Touchscreen Gestures may need its own
permissions because it is responsible for translating Edge touch into macOS
input.

## Known Limitations

- This app does not unlock native macOS multitouch for the XENEON EDGE.
- Touch behavior still depends on Touchscreen Gestures.
- Web tiles are web views, not full Safari tabs. Some sites may behave
  differently inside `WKWebView`.
- Keyboard input inside a web tile requires the web tile to have focus.
- Applications must be installed and launchable through `NSWorkspace`.
- The app does not currently control Edge hardware color, brightness, contrast,
  DDC, or HDR behavior.
- The XENEON display detection is practical, not magic. If macOS reports a
  strange display name/resolution, `ScreenResolver` may need tuning.

## Troubleshooting

### Dashboard Did Not Move To The Edge

Open Widget Settings, go to Display, and use Refresh. Confirm the display list
shows the XENEON panel.

If it does not, check macOS Displays settings and confirm the Edge is connected
as a display.

### Settings Opened On The Edge

Use the menu bar `Kira Edge -> Widget Settings` or `Command-,`. The app tries to
center settings on the primary non-XENEON display.

### An App Does Not Open

Confirm the application is installed in `/Applications` or
`/System/Applications` and that its name or bundle identifier matches the Apps
launcher entry.

### Web Tile Clicks Work But Typing Does Not

Click/tap inside the web tile once to give the embedded `WKWebView` keyboard
focus, then type.

### The Drawer Does Not Reveal From Swipe

Use the bottom `Menu` tab. Swipe translation can vary because Touchscreen
Gestures sits between the hardware and macOS. The visible tab is the dependable
control path.

### A Site Looks Too Small Or Too Large

Go to Widget Settings -> Widgets, select the web tile, and adjust Zoom.

### The App Crashes

Crash reports are written under:

```text
~/Library/Logs/DiagnosticReports/
```

Look for files named:

```text
XeneonEdgeWidgets-*.ips
```

## Build And Verification

Run tests:

```bash
swift test
```

The current tests verify:

- Default widget coverage.
- Disabled widgets are excluded.
- Presets load usable tiles.
- Web reload tokens update correctly.
- Widget catalog coverage.
- Adding catalog items selects the new tile.
- Appearance mode persistence and scheme resolution.
- Now Playing parser behavior and launcher-to-player transitions.

Build and run:

```bash
./script/build_and_run.sh
```

Install locally:

```bash
./script/install_app.sh
```

Bundle assembly also verifies the checksum-pinned Now Playing vendor tree, app
signature, and helper architectures. The app executable is checked against the
native build host; the current release artifact is arm64 rather than universal.

## Design Direction

This is moving toward a macOS-native, iCUE-like widget host for the Edge:

- Built-in native widgets for core Mac/system behaviors.
- Web tiles for sites and web apps.
- Apps launcher buttons for opening macOS applications.
- Now Playing through the vendored MediaRemote adapter.
- Presets for different modes: command, media, work, streaming, AI ops, home.
- Eventually, a plugin/manifest runtime could allow custom user widgets without
  editing Swift code.

Good next upgrades:

- Native Calendar widget through EventKit.
- Home Assistant API controls.
- Shortcuts launcher widget.
- BetterDisplay/DDC hooks if display controls are worth bringing back.
- Weather provider integration instead of a generic web tile.
- Stream Deck style action buttons.
- Profile import/export.
- Local widget manifest format.
- Optional lower-level touch bridge if Touchscreen Gestures becomes the limiting
  factor.

## Mental Model

Think of the app as three layers:

1. Host: macOS app, windows, menu bar, settings, persistence.
2. Runtime: tiles, web views, native widgets, app launchers, presets.
3. Hardware surface: the XENEON EDGE as a fullscreen second display, with
   Touchscreen Gestures translating touch into macOS input.

The strongest thing about this architecture is that it avoids fighting macOS for
native touch support. Instead, it makes the Edge useful as a purpose-built
dashboard today while leaving room to add deeper input support later.
