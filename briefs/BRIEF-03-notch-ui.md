# Brief 03 — Notch player

## Goal
The signature feature: album art beside the notch while playing, hover to expand into a full player with live progress. Looks native on macOS 26 (Liquid Glass).

## Read first
`ARCHITECTURE.md` → "Notch window". Brief 01 must be done (uses `NowPlayingStore`).

## Design intent (match behavior, not Oleo's pixels)
- **Collapsed:** while playing, a small rounded album-art chip sits immediately to the left of the notch, vertically centered in the menu-bar band. When paused it dims or fades after a short delay. When idle/Spotify closed: nothing visible.
- **Expanded (hover over the chip/notch area):** a panel grows down from the notch with spring animation: large artwork, title, artist, previous/play-pause/next, a progress bar with elapsed/remaining time, scrubbable by drag. Glass background (`.glassEffect()`), subtle shadow, artwork-tinted accent optional.
- Leaves on mouse exit after ~250 ms.
- Track change: art cross-fades, title slides.

## Tasks
1. `NotchGeometry`: find the notch screen, compute notch rect, left/right menu-bar areas, in screen coordinates. Unit test the math with fake screen values.
2. `NotchPanelController`: build the `NSPanel` per `ARCHITECTURE.md`, handle show/hide, screen changes, and Spaces/full-screen apps.
3. Hover handling: tracking area on the hit region only; collapsed state must not block menu bar items on the right of the notch or the rest of the bar.
4. `NotchView` (SwiftUI): collapsed chip and expanded player, driven by `NowPlayingStore`. Progress via `TimelineView(.animation)` active only while the panel is expanded and playing.
5. Controls call `SpotifyService`. Scrubbing: update locally while dragging, send `seek(to:)` on release.
6. Hook up the "Show notch player" menu toggle and `notchEnabled` setting.
7. Fallback for no-notch screens: centered top pill (simple version).

## Acceptance criteria
- Play in Spotify → chip appears beside the notch within ~1 s.
- Hover → expands smoothly (no jank, no flicker at the edges); mouse exit → collapses.
- All controls work; progress bar is accurate within 1 s and scrubbing works.
- Menu bar items (clock, Control Center, etc.) remain fully clickable.
- Works across multiple Spaces and above full-screen apps; survives plugging/unplugging an external display and closing/opening the lid.
- Spotify paused → dims; Spotify quit → disappears; Cadence never launches Spotify.
- Idle CPU ~0% when paused/collapsed; <3% while expanded and playing.

## Do not
- Use private APIs here.
- Copy code from boring.notch (GPL).
- Add visualizers, battery, calendar, etc.

## Report back
Screenshots or a short screen recording description if you can't capture; list of tuned constants (window level, delays); anything that differs on a notch Mac vs fallback.
