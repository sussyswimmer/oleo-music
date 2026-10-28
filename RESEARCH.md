# Research notes

## What Oleo Music is (from product page text)
- €5.99 one-time, instant .zip download, setup PDF, free updates. Mac only, macOS 26+, Apple silicon + Intel, works with/without notch.
- Features: art beside notch + hover player; lock screen player; click art for full-screen view (huge cover, ambient background from album colors, big clock); word-by-word synced lyrics; supports Apple Music, Spotify, YouTube Music, Amazon Music, TIDAL, Cider; menu bar app, launch at login; Liquid Glass design.
- I did not see the visuals (text fetch only). Open the page in a browser for UI reference.

## Feasibility by feature

| Feature | Feasible? | How | Risk |
|---|---|---|---|
| Notch player | Yes | NSPanel over the menu bar, notch geometry from `NSScreen` | Low |
| Now Playing (Spotify) | Yes | Spotify AppleScript dictionary + distributed notification | Low |
| Controls | Yes | AppleScript `playpause`, `next track`, `previous track`, `set player position` | Low |
| Lock screen player (display) | Yes, with private APIs | SkyLight space at very high level (proven by existing free apps) | Medium: private API, may break on macOS updates |
| Lock screen controls / click | Unknown | Depends on whether the window receives events over loginwindow | High: spike in Brief 02 |
| Full-screen art + ambient bg + clock | Yes | SwiftUI MeshGradient + palette extraction | Low (depends on lock screen click) |
| Word-by-word lyrics | Later | Line-synced from LRCLIB; word timing needs a source or interpolation | Medium |

## Why not the system Now Playing API
Apple restricted the MediaRemote Now Playing API for third-party apps starting macOS 15.4; open-source projects work around it with the `MediaRemoteAdapter` project. Since v1 is Spotify-only, none of that is needed. It only matters if we add other players later.

## Reference repos (read for ideas; check licenses before reading closely)
| Repo | Why | License notes |
|---|---|---|
| `sam-cookr/WeatherWidget` | Lock-screen widget via `SLSSpaceCreate` + `SLSSpaceSetAbsoluteLevel` (level 300), glass UI, same author as WidgetScreen | Listed MIT |
| `lakr233/SkyLightWindow` | Swift package wrapping the SkyLight space technique ("display your UI on lock screen") | Check LICENSE |
| `lqSky7/iphone-duo-macos-animation` (macTilt) | Release notes mention `SLSSpaceSetAbsoluteLevel 400` + `canBecomeVisibleWithoutLogin` over the password lock screen | Check LICENSE |
| `Raunik2/LivePaper` | Elevates a window above `CGShieldingWindowLevel` on lock | Listed MIT |
| `TheBoredTeam/boring.notch` | Notch geometry, expand/collapse behavior, MediaRemoteAdapter usage | **GPL-3.0** (some copies show CC BY-NC-ND). Concepts only. Never paste code. |
| WidgetScreen (free app by Sam Cook) | Existing proof that music widgets over the lock screen work without Screen Recording permission | App, not source |

## Spotify scripting facts
- Properties on `current track` include name, artist, album, album artist, duration, `artwork url`, id, spotify url, and more. `player position` is seconds.
- `com.spotify.client.PlaybackStateChanged` is the long-standing distributed notification for state/track changes. Confirm its `userInfo` keys on the current Spotify build.
- First script call triggers the Automation permission prompt.

## Open questions to resolve during build
1. Does the lock screen window receive clicks/hover on macOS 26.x? (Brief 02)
2. Do Apple Events to Spotify succeed while the Mac is locked? (Brief 02)
3. Exact `SLS*` signatures and best absolute level on the installed macOS version. (Brief 02)
4. Does the notch panel need to dodge menu bar extras on the right of the notch?
5. For lyrics later: is LRCLIB coverage good enough for my library? Is word timing available anywhere free?

## Legal/ethics
- Personal use, own code, own name and art. Fine.
- Don't ship Oleo's assets, name, icon, text or screenshots. Don't redistribute this app as a competing paid product without a proper rewrite and your own branding.
- Respect each reference repo's license (GPL-3.0 means copying code makes this app GPL).
- Using private APIs means no App Store; acceptable for personal use.

## Brief 02 findings: lock screen spike

**Status:** code written and pushed; **not yet run on the Mac.** Fill in the results table below from a test run, then decide GO / GO-display-only / NO-GO. Since Brief 04 the spike card has been replaced by the real lock screen player; the tests below run against that, and Debug builds still log everything they need.

### What runs on lock
- If **Lock screen player** is on (menu bar; off by default) and a track is playing or was paused less than 10 minutes ago, Cadence creates a SkyLight space at the chosen level, moves the card window into it and shows it. When the card goes away (unlock, nothing playing, display asleep) the window is removed and the space hidden and destroyed.
- Debug builds log to `~/Library/Logs/Cadence/lockscreen.log` (menu → **Show lock screen log**): lock and unlock and which signal reported them, space and window results, every input event that reaches the card, every Spotify script result while the card is up, now-playing changes, display sleep and wake. Release builds log there only after `defaults write com.maxwell.cadence LockScreenDiagnostics -bool YES`.
- Debug builds add **Lock screen level** (300 / 400 / 500) and **Lock screen controls** (on: interactive card; off: display-only, and clicks pass straight through) to the menu.

### Safety measures
- The window is card-sized, not full screen, and can never become key, so the password field keeps the keyboard.
- If a key press ever reaches Cadence while locked, the card disappears until the next unlock.
- Four unlock signals, any of which removes the card: `com.apple.screenIsUnlocked` (distributed), `com.apple.sessionagent.screenIsUnlocked` (Darwin notify), a regular app becoming active, and a 3 s check of `CGSSessionScreenIsLocked` from `CGSessionCopyCurrentDictionary` while locked. That check only acts after the session has reported "locked" during that lock, so a macOS that stopped reporting the key can't make it fire early.
- Turning **Lock screen player** off removes the card.
- If any required SkyLight symbol is missing, nothing is shown and the log says which.

### Private API signatures used, and where they were verified
| Function | Signature used | Source |
|---|---|---|
| `SLSMainConnectionID` | `() -> Int32` | SkyLightWindow, yabai |
| `SLSSpaceCreate` | `(cid, 1, 0) -> Int32` | SkyLightWindow |
| `SLSSpaceSetAbsoluteLevel` | `(cid, sid: UInt64, level) -> CGError` | SkyLightWindow; 64-bit space IDs per yabai and CGSInternal |
| `SLSShowSpaces` / `SLSHideSpaces` | `(cid, CFArray) -> Void` | SkyLightWindow, yabai, CGSInternal |
| `SLSSpaceAddWindowsAndRemoveFromSpaces` | `(cid, sid: UInt64, windows: CFArray, 7) -> CGError` | SkyLightWindow |
| `SLSSpaceDestroy` (else `CGSSpaceDestroy`), optional | `(cid, sid: UInt64) -> Void` | CGSInternal |

Sources: `lakr233/SkyLightWindow` (MIT, July 2026), `koekeishiya/yabai` (MIT, June 2026), `NUIKit/CGSInternal` (MIT, 2016). Read for signatures only; Cadence's implementation is its own. Space IDs are passed as 64-bit: a function declared with a 32-bit ID reads the low half of the same register, so this is correct either way.

### Notes from the reference repos
- **Destroying spaces:** SkyLightWindow and yabai never destroy one; CGSInternal declares `void CGSSpaceDestroy(CGSConnectionID, CGSSpaceID)`. Cadence resolves `SLSSpaceDestroy` (SkyLight's name for CGS calls), falls back to `CGSSpaceDestroy`, and if neither exists only hides the space (one empty hidden space per card until Cadence quits). The log says "destroyed" or "hidden" each time.
- **Lock notifications on macOS 26:** LivePaper (`Raunik2/LivePaper`, MIT, April 2026) listens for `com.apple.sessionagent.screenIsLocked` / `…Unlocked` through the Darwin notify center and calls it the reliable signal on Tahoe. Cadence listens to both that and the brief's `com.apple.screenIsLocked` and logs which arrives.
- Distributed notifications are held while an app is inactive unless registered with `.deliverImmediately`, which a menu-bar app needs.
- SkyLightWindow uses level 400 (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`), so 400 is the default. Its level list: 0 default, 100 setup assistant, 200 security agent, 300 screen lock, 400 notification center at screen lock, 500 boot progress, 600 VoiceOver.
- `sam-cookr/WeatherWidget` is no longer publicly reachable. `lqSky7/iphone-duo-macos-animation` has no license, so its code was not read.

### How to run the tests
1. Build and run the Debug build from Xcode. In the menu, turn on **Lock screen player**; leave **Lock screen level** at 400 and **Lock screen controls** on.
2. Play music in Spotify.
3. Press Ctrl+Cmd+Q. On the lock screen: look for the card, click each control and the artwork, hover over the card, scroll on it, then click the password field and unlock.
4. Open the menu → **Show lock screen log**. `input:` lines show which events arrived; `spotify:` lines show whether Spotify answered. Send it to Claude, or fill in the table.
5. Display sleep: lock, let the display turn off, wake it, check the card comes back.
6. Full sleep: Apple menu → Sleep (or close the lid), wake, check the lock screen.
7. Repeat steps 3–4 with levels 300 and 500.
8. Lock and unlock 10 times in a row; check that no card is left on the desktop and the menu still works.
9. If clicks didn't arrive in step 3: turn **Lock screen controls** off, lock again, and check the card has no controls and nothing on it looks tappable.

If the card ever gets in the way of unlocking, Touch ID still works, and the card removes itself if a key press reaches it.

### Results (fill in)
| # | Question | Result | Notes |
|---|---|---|---|
| 1 | Card appears over the password screen after Ctrl+Cmd+Q? | | |
| 2 | Comes back correctly after display sleep and wake? | | |
| 3 | Correct after full sleep and wake? | | |
| 4 | Clicks on the controls arrive (log: `input: leftMouseDown`) and Spotify responds? | | |
| 5 | Hover arrives (log: `input: mouseEntered` / `mouseMoved`)? | | |
| 6 | Scroll arrives (log: `input: scrollWheel`)? | | |
| 7 | Password field still usable after tapping the card? | | |
| 8 | Spotify reads succeed while locked (log: `spotify: refresh ok`)? | | |
| 9 | Spotify controls succeed while locked? | | |
| 10 | Artwork loaded while locked? | | |
| 11 | Unlock removes the card, menu bar app still works? | | |
| 12 | 10 lock/unlock cycles: no stuck window? | | |
| 13 | Level 300: above the password UI? Unlock OK? | | |
| 14 | Level 400: above the password UI? Unlock OK? | | |
| 15 | Level 500: above the password UI? Unlock OK? | | |
| 16 | Which lock notification arrived first (distributed / sessionagent)? Both? | | |
| 17 | Did the session report locked (log: "session reports locked: yes")? | | |
| 18 | Does the Liquid Glass card render properly over the lock screen? | | |
| 19 | Did macOS ask for Screen Recording or Accessibility? (must be no) | | |
| 20 | Spaces "destroyed" or only "hidden" in the log? | | |

### Recommendation
Pending results.
- **GO:** 1, 4, 7, 9, 11 and 12 pass.
- **GO-display-only:** 1, 7, 11 and 12 pass but clicks (4) don't arrive. Then set **Lock screen controls** off as the default.
- **NO-GO:** 1 fails, unlocking is ever affected, or a window gets stuck after unlock. Then Brief 04's player and Brief 05 are dropped and v1 is the notch player plus the menu bar app.

## Brief 04: lock screen player

**Status:** built ahead of the Brief 02 results, so it works for either outcome; not yet run on the Mac.

- Card: Liquid Glass, 360 pt wide, dark appearance; artwork, title, artist, progress with elapsed and remaining time (updated once a second, paused unless playing); ⏮ ⏯ ⏭ when interactive. Tapping the artwork is wired to a placeholder that Brief 05 replaces with full-screen art.
- Shown while locked if a track is playing, or paused less than 10 minutes ago. Hidden when Spotify is idle or quits, while the display sleeps, and after the keyboard safety trips.
- Constants (in `LockScreenController`): card center 45% up the screen, paused card kept 10 minutes, fail-safe every 3 s, space level 400 (setting), fade-in 0.3 s.

## Brief 05: full-screen art

**Status:** built for the case where clicks reach the lock screen; not yet run on the Mac. If Brief 02 finds they don't, the trigger needs your decision (below) before anything else is built.

- **Trigger:** tap the artwork on the lock screen card; tap anywhere to close. The window grows to the whole screen before the animation and shrinks back after it, and the artwork animates from the card into the big cover (matched geometry). Setting: **Full-screen album art** in the menu (on by default).
- **Layout:** date and time at the top (thin, 10% of the screen height, hours and minutes, redrawn once a minute); cover 50% of the screen height with a soft shadow; title and artist; a thin progress bar.
- **Palette** (`PaletteExtractor`, unit-tested with synthetic pixels): downsample to 32 × 32; skip transparent pixels and near-black, near-white, grey and dull ones (brightness under 0.2 or saturation under 0.25); group the rest into 24 hues × 4 saturations × 4 brightnesses; drop groups under 1% of the pixels; rank by size × (0.5 + saturation × brightness); keep up to 5 colors at least 0.22 apart (RGB distance). One or two colors get darker and slightly shifted shades added to make 3. No vivid colors at all (black and white, grey, very dark covers) gives a fixed indigo / plum / teal palette.
- **Background:** a 3 × 3 mesh gradient of the palette (darker corners), drifting on slow unrelated cycles, darkened 28% for legible white text. It cross-fades over 1 s when the palette changes.
- **Cost:** the mesh renders at a quarter of the screen size, is softened, then scaled up, which is smooth anyway and cheap on the GPU. 20 fps while playing, 2 fps while paused, stopped when nothing is loaded. The progress bar updates once a second, the clock once a minute.
- **Closing with a key press isn't possible.** The brief asks for "tap again (or press a key)". Key presses on the lock screen go to the password field, not to Cadence, and seeing them would need Accessibility permission, which Cadence must not ask for. So it closes on a tap. Typing the password still works while the art is showing (the field keeps the keyboard), and Touch ID works.

**If clicks don't reach the lock screen**, full-screen art needs another trigger. Options to choose from (not built):
1. Open automatically after N seconds locked while playing (for example 10 s); close on unlock or display sleep.
2. A setting, "Always full-screen when locked", that skips the card entirely.
3. No full-screen art in display-only mode.
