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

**Status:** spike code written and pushed; **not yet run on the Mac.** Fill in the results table below from a test run, then decide GO / GO-display-only / NO-GO.

### What the spike does
- On lock, if **Lock screen player** is on (menu bar; off by default), Cadence creates a SkyLight space at the chosen level, moves a small card window into it and shows it. On unlock it removes the window and hides the space.
- The card shows artwork, title, artist, ⏮ ⏯ ⏭, a clock ticking every second (proves it keeps rendering), an input-event counter, a hover counter, the space level, and the last event type in red.
- Everything is logged to `~/Library/Logs/Cadence/lockscreen.log` (Debug builds: menu → **Show lock screen log**): lock/unlock notifications and which source sent them, space and window results, every input event, every Spotify script result while locked, now-playing changes, sleep/wake.
- Debug builds add **Lock screen level** (300 / 400 / 500) to the menu.

### Safety measures
- The window is card-sized, not full screen, and can never become key, so the password field keeps the keyboard.
- If a key press ever reaches Cadence while locked, the card removes itself immediately.
- Three unlock signals, any of which removes the card: `com.apple.screenIsUnlocked` (distributed), `com.apple.sessionagent.screenIsUnlocked` (Darwin notify), and a 3 s fail-safe reading `CGSSessionScreenIsLocked` from `CGSessionCopyCurrentDictionary`. The fail-safe only acts after the session has reported "locked" at least once during that lock, so a macOS that stopped reporting the key can't make it fire early.
- Turning **Lock screen player** off removes the card.
- If any SkyLight symbol is missing, nothing is shown and the log says which symbol.

### Private API signatures used, and where they were verified
| Function | Signature used | Source |
|---|---|---|
| `SLSMainConnectionID` | `() -> Int32` | SkyLightWindow, yabai |
| `SLSSpaceCreate` | `(cid, 1, 0) -> Int32` | SkyLightWindow |
| `SLSSpaceSetAbsoluteLevel` | `(cid, sid: UInt64, level) -> CGError` | SkyLightWindow; 64-bit space IDs per yabai |
| `SLSShowSpaces` / `SLSHideSpaces` | `(cid, CFArray) -> Void` | SkyLightWindow, yabai |
| `SLSSpaceAddWindowsAndRemoveFromSpaces` | `(cid, sid: UInt64, windows: CFArray, 7) -> CGError` | SkyLightWindow |

Sources: `lakr233/SkyLightWindow` (MIT, July 2026) and `koekeishiya/yabai` (MIT, June 2026). Read for signatures only; Cadence's implementation is its own. Space IDs are passed as 64-bit: a function declared with a 32-bit ID reads the low half of the same register, so this is correct either way.

### Notes from the reference repos
- **No reference declares a way to destroy a space**, so the spike hides it instead. That leaves one empty, hidden space per lock until Cadence quits. Decide in Brief 04 whether that matters, or whether to create one space at launch and reuse it, as SkyLightWindow does.
- **Lock notifications on macOS 26:** LivePaper (`Raunik2/LivePaper`, MIT, April 2026) listens for `com.apple.sessionagent.screenIsLocked` / `…Unlocked` through the Darwin notify center and calls it the reliable signal on Tahoe. The spike listens to both that and the brief's `com.apple.screenIsLocked` and logs which arrives; only the first shows the card.
- Distributed notifications are held while an app is inactive unless registered with `.deliverImmediately`, which a menu-bar app needs.
- SkyLightWindow uses level 400 (`kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock`), so 400 is the default. Its level list: 0 default, 100 setup assistant, 200 security agent, 300 screen lock, 400 notification center at screen lock, 500 boot progress, 600 VoiceOver.
- `sam-cookr/WeatherWidget` is no longer publicly reachable. `lqSky7/iphone-duo-macos-animation` has no license, so its code was not read.

### How to run the tests
1. Build and run the Debug build from Xcode. Turn on **Lock screen player** in the menu, and leave **Lock screen level** at 400.
2. Play music in Spotify.
3. Press Ctrl+Cmd+Q. On the lock screen: look for the card, click each button, hover over the card, scroll on it, then click the password field and unlock.
4. Open the menu → **Show lock screen log** and read what happened (or send it to Claude).
5. Display sleep: lock, let the display turn off (or press the display-off key if you have one), wake it, check the card.
6. Full sleep: Apple menu → Sleep (or close the lid), wake, check the lock screen.
7. Repeat steps 3–4 with levels 300 and 500.
8. Lock and unlock 10 times in a row; then check that no card is left on the desktop and the menu still works.

If the card ever gets in the way of unlocking, Touch ID still works, and the card removes itself if a key press reaches it.

### Results (fill in)
| # | Question | Result | Notes |
|---|---|---|---|
| 1 | Card appears over the password screen after Ctrl+Cmd+Q? | | |
| 2 | Still there and correct after display sleep and wake? | | |
| 3 | Still there and correct after full sleep and wake? | | |
| 4 | Button clicks register (counter, log)? | | |
| 5 | Hover registers? | | |
| 6 | Scroll registers? | | |
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
| 17 | Did the session dictionary report locked (fail-safe usable)? | | |
| 18 | Does the Liquid Glass card render properly over the lock screen? | | |
| 19 | Did macOS ask for Screen Recording or Accessibility? (must be no) | | |

### Recommendation
Pending results.
- **GO:** 1, 4, 7, 9, 11 and 12 pass.
- **GO-display-only:** 1, 7, 11 and 12 pass but clicks (4) don't arrive.
- **NO-GO:** 1 fails, unlocking is ever affected, or a window gets stuck after unlock.
