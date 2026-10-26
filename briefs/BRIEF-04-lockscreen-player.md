# Brief 04 — Lock screen player

## Goal
Turn the Brief 02 spike into the real lock screen player: artwork, title, artist, progress and controls, styled like an iPhone Now Playing widget on macOS 26 glass.

## Preconditions
Brief 02 recommendation was **GO** or **GO-display-only**. If NO-GO, skip this brief and Brief 05, and tell me.

## Read first
`ARCHITECTURE.md` → "Lock screen", the findings you appended to `RESEARCH.md`, and `BRIEF-02`.

## Tasks
1. `LockScreenView`: glass card positioned where it won't collide with the clock/password UI (lower-middle area; make position a constant to tune). Contents: artwork (rounded), title, artist, progress bar with times, ⏮ ⏯ ⏭ buttons.
2. Only show the card when there is a track and state is playing or recently paused. Hide fully when Spotify is idle.
3. If Brief 02 found input works: wire up controls and tap-on-artwork (handoff to Brief 05). If **display-only**: remove interactive affordances, show progress read-only, and skip tap handling.
4. Progress: `TimelineView(.periodic(by: 1))` (1 Hz is enough on the lock screen).
5. Lifecycle hardening:
   - Rebuild the space/window on every lock event, tear down on unlock.
   - Handle track changes while locked (art cross-fade).
   - Handle sleep/wake while locked (window must reappear).
   - Fail-safe unlock timer from Brief 02 stays.
6. Respect `lockScreenEnabled`. Wire the menu bar toggle.
7. Remove debug UI and logging noise from the spike (keep file logging behind a debug flag).

## Acceptance criteria
- Lock while a song plays → card shows the right track within 1 s of the lock screen appearing.
- Track changes while locked update the card.
- Controls work if Brief 02 said they can; otherwise card is clearly display-only and nothing looks clickable.
- Lock/unlock 20 times, sleep/wake 5 times: no stuck windows, no crashes, unlock always works.
- Unlocking never reveals a leftover window on the desktop.
- CPU while locked and playing < 2%; ~0% while locked and paused.

## Do not
- Show anything sensitive or add a way to bypass the lock.
- Request Screen Recording or Accessibility.

## Report back
What works vs. display-only, tuned constants, any macOS 26.x quirks.
