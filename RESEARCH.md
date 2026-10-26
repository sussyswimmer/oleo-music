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
