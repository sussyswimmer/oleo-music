# Brief 01 — Spotify service + NowPlayingStore

## Goal
A reliable, low-overhead model of what Spotify is playing, plus working controls. Verified with a throwaway debug window in the menu bar before any real UI exists.

## Read first
`ARCHITECTURE.md` → "Now Playing (Spotify only)" and "Key gotchas".

## Tasks
1. `Track` model: `id` (Spotify URI), `title`, `artist`, `album`, `durationSeconds` (convert from ms), `artworkURL`.
2. `PlaybackState` enum: `.idle` (Spotify not running or stopped), `.paused`, `.playing`.
3. `NowPlayingStore` (`@Observable`, `@MainActor`): `track: Track?`, `state`, `artwork: NSImage?`, and a position anchor `(positionSeconds, anchorDate)` with a computed `currentPosition(at:)` that extrapolates only while playing.
4. `SpotifyService` (actor):
   - `isRunning` via `NSRunningApplication` with bundle ID `com.spotify.client`. **Every AppleScript call must be guarded by this.**
   - `refresh()` runs one batched AppleScript that returns state, position, and track fields in a single call (delimited string), parse safely (titles can contain any character; use a delimiter such as ASCII unit separator).
   - Observe `com.spotify.client.PlaybackStateChanged` on `DistributedNotificationCenter.default()`; on fire, call `refresh()`. Log the notification's `userInfo` keys once so we know what's available.
   - Observe `NSWorkspace` didLaunch/didTerminate for Spotify to flip to `.idle` immediately on quit.
   - Slow safety poll (5 s) only while `.playing`.
   - Controls: `playPause()`, `next()`, `previous()`, `seek(to:)`. After each, `refresh()`.
5. `ArtworkLoader`: fetch `artwork url`, small in-memory cache, keep previous image until the new one is ready.
6. Temporary debug menu item "Debug now playing…" opening a small window showing title/artist/art/state/position and buttons for the four controls.

## Acceptance criteria (verify by running with Spotify)
- Play a track → debug window shows correct title, artist, art within ~1 s.
- Pause/resume/next/previous from Spotify itself → window updates within ~1 s without waiting for the 5 s poll.
- Buttons in the debug window control Spotify.
- Seek works and the position anchor corrects immediately.
- **Quit Spotify → state goes idle; Cadence does NOT relaunch Spotify.** Check Activity Monitor.
- Track titles with commas, quotes, emoji, or `|` parse correctly.
- First run triggers the Automation permission prompt; after allowing, everything works. Report what happens if the user denies it (show an "Allow Cadence to control Spotify" state; do not crash).
- Cadence idle CPU ~0% when Spotify is paused or closed.

## Do not
- Run AppleScript on the main thread.
- Use any private API here.
- Poll faster than 5 s.

## Report back
The `userInfo` keys of the notification, any parse edge cases found, and the measured idle CPU.
