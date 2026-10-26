# CLAUDE.md — instructions for Claude Code

## Project
Personal macOS 26 menu-bar app: notch music player + lock screen player + full-screen album art, for the Spotify desktop app. Read `README.md` and `ARCHITECTURE.md` first. Work from one `BRIEF-XX` file at a time.

## Environment
- Xcode 26+, Swift 6, macOS 26 deployment target, SwiftUI + AppKit.
- App is a menu-bar agent: `LSUIElement = YES`, no Dock icon.
- **App Sandbox OFF.** Add `NSAppleEventsUsageDescription` to Info.plist. If hardened runtime is on, add the `com.apple.security.automation.apple-events` entitlement.
- Sign with "Sign to Run Locally". No paid developer account, no notarization, no App Store.
- No third-party dependencies unless a brief says so. Do not add Swift packages without asking.

## Rules
1. **Never launch Spotify.** `tell application "Spotify"` launches the app if it isn't running. Always check `NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")` first.
2. **Never run AppleScript on the main thread.** Use one serial background queue/actor; publish results to a main-actor `@Observable` store.
3. **Private APIs live in one place**: `Sources/LockScreen/SkyLightBridge.swift`. Resolve symbols at runtime (`dlopen`/`dlsym`) and degrade gracefully if missing. Nothing else in the codebase may touch private APIs.
4. **No GPL/NC code copying.** Reference repos are for ideas and API names only. Write our own implementation. Check each repo's LICENSE before even reading closely. `boring.notch` is GPL-3.0 (one fork lists CC BY-NC-ND) — read for concepts only, never paste.
5. **No Oleo branding**: no name, icon, copy, artwork, or screenshots in the app or repo.
6. Verify private API signatures against the reference repos or by testing. Do not trust memory for exact `SLS*` function signatures.
7. Keep idle cost near zero: no polling loops faster than needed, pause timers when nothing is playing or the screen is asleep.
8. Small commits, one per logical step. Commit message format: `brief-03: add notch geometry`.

## How to work
- Plan briefly, then implement. Build with `xcodebuild -scheme Cadence -destination 'platform=macOS' build` after each step and fix warnings.
- Each brief has **Acceptance criteria**. Do not call a brief done until every item is verified by running the app, not just compiling. If something can only be verified by a human (e.g. looking at the lock screen), stop and tell me exactly what to check.
- If a brief's assumption is wrong (API missing, behavior differs on macOS 26), stop and report findings and options instead of silently working around it.
- Prefer SwiftUI for content, AppKit (`NSPanel`, `NSWindow`) for window behavior.
- Use `@Observable` stores, `async/await`, and `@MainActor` for UI state.

## Layout
```
Cadence/
  App/            CadenceApp.swift, AppDelegate, MenuBar, Settings
  NowPlaying/     SpotifyService, NowPlayingStore, Track, ArtworkLoader
  Notch/          NotchGeometry, NotchPanelController, NotchView
  LockScreen/     SkyLightBridge (private APIs), LockScreenController, LockScreenView
  FullScreenArt/  AmbientBackground, PaletteExtractor, BigClockView
  Shared/         Theme, Glass helpers, Formatting
```
