# Contributing

Thanks for helping out! This is a small, focused codebase — SwiftPM, SwiftUI,
Swift 6 strict concurrency, no third-party dependencies.

## Getting started

```sh
swift build                  # must stay at 0 errors, 0 warnings
swift test                   # must pass
script/build_and_run.sh run  # assemble + launch the real .app bundle
```

You don't need a XENEON Edge to develop: without one connected, the dashboard
is a normal window and Edge-specific actions report "Edge display not found."

## Ground rules

- **Swift 6 strict concurrency — the one hard rule:** never do main-actor work
  (or use `MainActor.assumeIsolated`) inside a callback that a system framework
  may invoke off the main thread (`NSWorkspace` notifications,
  `ASWebAuthenticationSession`, CoreBluetooth, `URLSession`).
  Extract `Sendable` values and hop with `Task { @MainActor in … }`, or keep
  the handler fully nonisolated. This rule exists because violating it crashed
  the app three separate times during development.
- Keep the app permission-free. PRs that add Accessibility, Automation, or
  Screen Recording requirements need a very strong reason.
- Persisted-model changes must decode tolerantly: unknown widget kinds and
  malformed tiles are dropped via `LossyArray`, never fatal.
- Match the existing code style: `// MARK:` sections, doc comments that explain
  *why*, no comment noise.

## PRs

- One focused change per PR.
- `swift build` with zero warnings and `swift test` green.
- If you touched the URL bridge, update the grammar table in the README.
