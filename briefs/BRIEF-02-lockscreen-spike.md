# Brief 02 — Lock screen feasibility spike (go / no-go)

## Goal
Find out, with the smallest possible code, what is actually possible on **my** Mac (macOS 26.x): can our own window draw over the lock screen, can it receive clicks, and can we still talk to Spotify while locked. Output is a findings report plus a tiny `SkyLightBridge`, not a finished feature.

## Read first
`ARCHITECTURE.md` → "Lock screen". `RESEARCH.md` → reference repos. Check each repo's LICENSE before reading code; take API names and the general technique only.

## Background
Free apps (e.g. WidgetScreen, WeatherWidget) already draw over the lock screen without Screen Recording permission by moving a normal window into a SkyLight "space" with a very high absolute level. Reported pieces: `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel` (levels around 300–400 reported), `SLSShowSpaces`, `SLSSpaceAddWindowsAndRemoveFromSpaces`, `SLSMainConnectionID`, and setting `canBecomeVisibleWithoutLogin` on the window. **Signatures must be verified against the reference repos or by testing, not from memory.**

## Tasks
1. Create `Sources/LockScreen/SkyLightBridge.swift`:
   - Resolve the needed symbols at runtime from the SkyLight framework (`dlopen` / `dlsym`), expose a small Swift API: `createSpace(level:)`, `addWindow(_:to:)`, `showSpace`, `hideSpace`, `destroySpace`.
   - If any symbol is missing, return a clear "unsupported" error (no crash).
2. `LockScreenController`:
   - Observe `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` on `DistributedNotificationCenter`.
   - On lock: build a borderless `NSWindow` (SwiftUI content) sized for the main display, set `canBecomeVisibleWithoutLogin`, create a fresh space, add the window, show it.
   - On unlock: hide/destroy the space and close the window.
3. Spike UI inside that window (throwaway): a rounded glass card at the lower-middle of the screen containing: the current title/artist/artwork from `NowPlayingStore`, three buttons (⏮ ⏯ ⏭), a live-updating timestamp, and a counter that increments on any click/hover so we can see input arriving. Also a red "last event" label showing the most recent mouse/key event type received.
4. Log to a file (`~/Library/Logs/Cadence/lockscreen.log`) because we can't watch the console while locked: lock/unlock events, space creation results, every Spotify AppleScript call result while locked, every input event.
5. Test matrix (I will run these; give me the exact steps and a results table to fill):
   - Lock with Ctrl+Cmd+Q → does the card appear over the password screen?
   - Does it render correctly after waking from display sleep? After full sleep?
   - Does a click on the buttons register? Does hover register? Does scroll?
   - Does tapping the card keep the password field usable?
   - Do Spotify AppleScript reads and controls succeed while locked?
   - Is the artwork image (network fetch) still loaded while locked?
   - Unlock → does everything disappear and does the notch/menubar app still work?
   - Try a few absolute levels and report which one draws above the password UI but does not break unlock.

## Acceptance criteria
- A written findings section (append to `RESEARCH.md`) answering every row of the test matrix with yes/no/notes.
- A clear recommendation: **GO** (display + controls), **GO-display-only** (no input), or **NO-GO**, with reasoning.
- The bridge never crashes the app if SkyLight symbols are missing, and never leaves a stuck window after unlock (verify by locking/unlocking 10 times).

## Safety
- The window must never prevent unlocking. Always provide a fail-safe: if the unlock notification is missed, a timer checks `CGSessionCopyCurrentDictionary` (`CGSSessionScreenIsLocked`) every few seconds and tears the window down.
- Keep the spike behind the `lockScreenEnabled` setting, default OFF.

## Do not
- Poll aggressively while locked.
- Request Screen Recording or Accessibility permission. If macOS asks, stop and report.
- Polish the UI. That is Brief 04.

## Report back
The findings table, the recommended GO/NO-GO, and which absolute level worked.
