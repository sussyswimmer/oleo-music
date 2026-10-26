# Architecture

## Overview
```
Spotify.app ──AppleScript + distributed notification──▶ SpotifyService (actor)
                                                              │
                                                              ▼
                                                   NowPlayingStore (@Observable, @MainActor)
                                                   ├─▶ NotchPanelController ─▶ NotchView
                                                   ├─▶ LockScreenController ─▶ LockScreenView ─▶ FullScreenArtView
                                                   └─▶ MenuBar / Settings
```
One source of truth (`NowPlayingStore`). All UI reads it; all controls call `SpotifyService` methods.

## Now Playing (Spotify only)
**Why Spotify-only is easy:** Spotify's scripting dictionary exposes everything we need, so we avoid the system-wide MediaRemote API (which Apple locked down for third-party apps in macOS 15.4+).

Reads (AppleScript, `tell application "Spotify"`):
- `player state` (playing/paused/stopped), `player position` (seconds)
- on `current track`: `name`, `artist`, `album`, `duration` (ms), `artwork url`, `id` (Spotify URI)

Writes: `playpause`, `next track`, `previous track`, `set player position to N`.

**Change detection:** observe the distributed notification `com.spotify.client.PlaybackStateChanged` (`DistributedNotificationCenter.default()`); on fire, refresh via AppleScript. Its `userInfo` also carries track info and state (inspect at runtime to confirm exact keys on current Spotify) and can be used to skip a script call.

**Progress bar:** don't poll fast. Store `(position, timestamp, isPlaying)` at each refresh and extrapolate in the UI with `TimelineView(.animation)` only while visible and playing. Resync on every notification, after scrubs, and with a slow (~5 s) safety poll while playing.

**Not running:** observe `NSWorkspace` launch/terminate notifications for `com.spotify.client`. If not running, set store to `.idle` and show nothing. Never script Spotify unless running.

**Artwork:** download `artwork url` with `URLSession`, cache in memory by URL (small LRU), decode to `NSImage`. Show previous art until the new one loads (no flicker).

## Notch window
- `NSPanel`, styleMask `[.borderless, .nonactivatingPanel]`, transparent background, no shadow.
- `level`: above the menu bar (e.g. `.mainMenu + 1`; tune), `collectionBehavior`: `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- Pick the built-in screen with a notch: `NSScreen.screens.first { $0.safeAreaInsets.top > 0 }`.
- Notch geometry: height = `safeAreaInsets.top`; left/right menu-bar areas from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`; notch width = `frame.width - left.width - right.width`.
- States: **collapsed** (art chip to the left of the notch, in the menu-bar band, optional tiny visualizer on the right), **expanded** (hover; grows downward from the notch, glass background, full controls). Hover via `NSTrackingArea` or SwiftUI `.onHover`; add a short open/close delay to avoid flicker.
- Collapsed state should not block clicks on menu bar items outside the small art chip (size the panel tightly or override `hitTest`).
- Rebuild on `NSApplication.didChangeScreenParametersNotification`.
- If no notch screen is found, fall back to a centered pill at the top of the main screen (low priority).

## Lock screen
- Detect lock/unlock via distributed notifications `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` (also handle display sleep/wake).
- The player is our own `NSWindow` hosting SwiftUI. On lock, create a SkyLight space at a very high absolute level and move the window into it so it draws over the lock screen UI; on unlock, remove it and close the window.
- Reported working technique (MIT/other repos listed in `RESEARCH.md`): `SLSSpaceCreate` + `SLSSpaceSetAbsoluteLevel` (levels ~300–400 reported) + `SLSShowSpaces` + `SLSSpaceAddWindowsAndRemoveFromSpaces`, and `canBecomeVisibleWithoutLogin` on the window. **Verify exact signatures against those repos in Brief 02.**
- Rebuild the space on every lock event; do not reuse across sleep/wake.
- Input is uncertain: clicks on a window over the lock screen may or may not be delivered. Brief 02 measures this. If clicks don't work, the lock screen player is display-only and full-screen art is triggered another way (or dropped).
- Apple Events to Spotify while locked: unverified; Brief 02 measures this too.

## Full-screen art
- A larger view of the same lock screen window (animate size/corner radius, matched-geometry style).
- Background: palette from artwork (downsample to ~32×32, pick 3–5 dominant, vibrant colors, avoid near-black/near-white), rendered with SwiftUI `MeshGradient` slowly animating, plus blur. Cross-fade on track change.
- Big clock: `TimelineView(.periodic)` once per second (or per minute if no seconds), large light-weight font.

## Menu bar + settings
- `MenuBarExtra` with: show/hide notch player, launch at login (`SMAppService.mainApp`), lock screen player on/off, quit.
- Settings kept in `@AppStorage`.

## Permissions
- Automation → Spotify (prompted on first AppleScript; test by resetting with `tccutil reset AppleEvents`).
- No Screen Recording, Accessibility, or Input Monitoring should be needed. If any gets requested, something is wrong.

## Key gotchas
1. AppleScript to a non-running app launches it. Guard every call.
2. Spotify's `duration` is milliseconds; `player position` is seconds.
3. Private APIs may change between macOS point releases; isolate and feature-flag them.
4. Window level fights with the menu bar and full-screen apps; test with a full-screen app and multiple Spaces.
5. Lock screen windows can vanish after sleep/wake; recreate on events.
6. Don't keep timers/animations running while locked-and-asleep or when nothing plays.
