# Kira Edge

**Kira Edge** is a native macOS widget dashboard for the **Corsair XENEON
EDGE** (2560×720 touch strip) — the Mac widget app Corsair never shipped. It
treats the Edge as a dedicated ambient display: a fullscreen dashboard of
glanceable widgets lives on the strip, a settings window stays on your main
display, and a `xeneonedge://` URL bridge lets a Stream Deck (or any script)
drive the whole thing.

> **Not affiliated with Corsair.** XENEON is a trademark of Corsair Memory, Inc.
> This is an independent, unofficial companion app. It complements — and does
> not replace — Corsair's own Touchscreen Gestures software.

![The Kira Edge dashboard running on a Corsair XENEON EDGE — Clock, System, Apps, and a web tile](docs/hero.png)

## Widgets

- **Clock** — time/date, Google Calendar agenda + month grid, current weather
  and forecast (hourly or 7-day)
- **System** — CPU, memory, disk, network throughput, public/local IP, Mac and
  Bluetooth accessory batteries
- **Apps** — a launcher grid; tap an icon to open the app
- **Note** — pinned text, per profile
- **Web** — any site or dashboard in a tile (zoom, reload interval, desktop
  user-agent, readable-CSS injection)
- **Power** — battery detail

## Features

- **Six profiles** (Command, Media, Work, Streaming, AI Ops, Home), each with
  its own pages of widgets. Switch from the menu-bar extra, **⌘1–⌘6**, the
  settings window, or a URL.
- **Meeting auto-switch** — optionally loads a chosen profile a few minutes
  before your next calendar event.
- **Stream Deck / automation bridge** — every important action is a URL
  (table below). A Stream Deck button is just an "Open URL" action.
- **Mute overlay** — a full-screen MUTED banner for the strip, one URL away.
- Appearance modes (dark/light/system), animated motion backdrops, profile
  export/import, launch at login.
- **No scary permissions.** The app needs no Accessibility, no Automation, and
  no Screen Recording. (Bluetooth is requested only if you want accessory
  batteries in the System widget; Google Calendar is optional OAuth.)

## Requirements

- macOS 14 or later (Apple Silicon or Intel)
- Designed for the XENEON EDGE's 2560×720 panel, but runs on any display —
  without an Edge connected the dashboard is a normal resizable window
- A Swift 6.0+ toolchain (Xcode 16 or newer) to build from source

## Install

Grab the notarized DMG from [Releases](../../releases), drag the app to
Applications, launch. That's it — no permission prompts.

## Build from source

```sh
git clone https://github.com/chadvegas/kira-edge.git
cd kira-edge
swift build                     # library + tests
script/build_and_run.sh run     # assemble the .app bundle, sign, launch
script/install_app.sh           # install/refresh /Applications copy
```

`swift test` runs the unit tests. See [SHIPPING.md](SHIPPING.md) to produce a
notarized DMG of your own fork.

The optional Apple Watch battery helper (`Helpers/xeneon-watch-battery.c`) is
compiled automatically by `build_and_run.sh` when Homebrew `libimobiledevice`
and `pkg-config` are installed, and skipped otherwise — without it the System
widget simply omits watch batteries.

## Google Calendar setup (optional)

The public build ships without a Google OAuth client, so calendar sync is
bring-your-own-ID (5 minutes, free, no secret involved — it's a PKCE client):

1. Create a project at [console.cloud.google.com](https://console.cloud.google.com)
   and enable the **Google Calendar API**.
2. Configure the OAuth consent screen (External → Testing) and add your own
   Google account as a **Test user**.
3. Credentials → **Create credentials → OAuth client ID** → type **iOS**,
   bundle ID `com.chadvegas.XeneonEdgeWidgets` (or your fork's bundle ID).
4. Copy the client ID (`…apps.googleusercontent.com`).
5. In the app: select the Clock widget → **Content** → Google Calendar →
   **Advanced** → paste the ID → **Connect Google Calendar**.

Forks that want one-click calendar for their users can hardcode a client ID in
`GoogleAuthService.bundledClientID`.

## Stream Deck / URL bridge

Anything that can run `open "xeneonedge://…"` can drive the dashboard — Stream
Deck "Open" actions, Raycast, shell scripts, cron.

| URL | Action |
| --- | --- |
| `xeneonedge://profile/<name>` | Switch profile (`work`, `ai-ops`, `AI Ops`… all match) |
| `xeneonedge://page/next` · `page/prev` · `page/<n>` | Page navigation (zero-based index) |
| `xeneonedge://focus/<widget>` · `focus/clear` | Focus one widget full-screen / show all (`clock`, `system`, `power`, `launcher`, `note`, `web`) |
| `xeneonedge://edge/send` | Move the dashboard to the XENEON Edge |
| `xeneonedge://web/reload` | Reload every web tile |
| `xeneonedge://appearance/dark` · `light` · `system` | Appearance mode |
| `xeneonedge://motion/pause` · `resume` · `toggle` | Motion backdrop |
| `xeneonedge://mute/on` · `off` · `toggle` | MUTED overlay |

Outcomes are logged via `os.Logger` (subsystem
`com.chadvegas.XeneonEdgeWidgets`, category `URLRouter`) if you want to verify
routing:

```sh
log stream --level info --predicate 'subsystem == "com.chadvegas.XeneonEdgeWidgets" AND category == "URLRouter"'
```

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘1 – ⌘6 | Switch profile |
| ⌘⇧E | Send dashboard to the Edge |
| ⌘⇧D | Toggle Edge mode / controls window |
| ⌘⇧W | Edit widgets |
| ⌘⇧P | Pin dashboard |
| ⌘, | Widget Settings |

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The project is
Swift 6 with strict concurrency; the one hard rule is documented there.

## License

[MIT](LICENSE)
