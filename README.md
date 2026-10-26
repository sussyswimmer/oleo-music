# Cadence (working name) — a free Oleo Music-style player for my Mac

> Working name only. Rename freely. Do **not** reuse Oleo's name, icon, copy, or artwork anywhere in this app.

## What this is

A personal, free rebuild of the idea behind Oleo Music (oleoclub.store/products/oleo-music, €5.99): a lightweight macOS menu-bar app that turns the notch and lock screen into a Now Playing surface, like the iPhone.

Built for **my own Mac only**: notch MacBook, macOS 26 Tahoe, **Spotify desktop app only**. Not for the App Store, not for redistribution.

## Scope

### v1 (build this)
1. **Notch player** — while a song plays, small album art sits next to the notch. Hover to expand into a full player: artwork, title, artist, play/pause, previous, next, live progress bar (scrubbable).
2. **Lock screen player** — when the Mac is locked, a player stays visible: artwork, song, artist, controls (controls are best-effort, see feasibility notes).
3. **Full-screen album art** — click the artwork on the lock screen to expand: huge cover, ambient animated background derived from the cover colors, big clock.
4. **Menu-bar app** — no Dock icon, settings window, launch at login toggle.

### Later (not v1)
- Synced lyrics (line-synced, then karaoke word-by-word). See `BRIEF-07-lyrics-later.md`.
- Other players (Apple Music, browsers).

## Product reference (what Oleo Music does, per its product page)
- Artwork beside the notch while playing; hover opens full player with play/pause/skip and live progress bar.
- Lock screen player with artwork, song, artist, controls.
- Click lock screen artwork → full-screen view: huge cover, ambient background from album colors, big clock.
- Word-by-word synced lyrics, karaoke style.
- Supports many music apps; made for macOS 26 Liquid Glass; menu bar, launch at login, works with and without a notch.

I only read the page text, not the visuals. Before polishing the UI, look at the product page (and any screenshots/videos on it) for layout and animation reference, then design my own version. Match the *behavior*, not the pixels or branding.

## Tech decisions (already made)
| Decision | Choice |
|---|---|
| Language/UI | Swift 6, SwiftUI + AppKit (NSPanel for windows) |
| Min OS | macOS 26 (Liquid Glass via `.glassEffect()`) |
| Music source | Spotify desktop app via AppleScript + `com.spotify.client.PlaybackStateChanged` distributed notification |
| Lock screen | SkyLight private APIs (own SwiftUI window moved into a high-level compositor space) |
| Sandbox | **Off** (private APIs + Apple Events) |
| Dependencies | None to start. Hand-roll everything. |
| Signing | "Sign to Run Locally" (ad hoc). No paid Apple Developer account needed. |
| Cost | Free: Xcode + a Mac |

## Repo docs
- `CLAUDE.md` — standing instructions for Claude Code. Copy into the repo root.
- `ARCHITECTURE.md` — modules, data flow, window levels, key gotchas.
- `RESEARCH.md` — feasibility findings, reference repos, licenses, risks.
- `BRIEF-00` … `BRIEF-07` — one self-contained task brief per phase. Give Claude Code one at a time, in order.

## Build order
00 bootstrap → 01 Spotify service → **02 lock-screen spike (go/no-go)** → 03 notch UI → 04 lock screen player → 05 full-screen art → 06 polish + install → 07 lyrics (later).

The spike is done early on purpose. The lock screen is the riskiest piece; if it fails, v1 shrinks to notch + menu bar and that's still a good app.

## Definition of done for v1
- Launch app → Spotify plays → art appears beside notch → hover expands player → controls work.
- Lock Mac (Ctrl+Cmd+Q) → player shows over the lock screen with correct track → click artwork → full-screen art + clock.
- Unlock → lock screen windows disappear cleanly, notch player continues.
- Survives sleep/wake, Spotify quit/relaunch, track changes, and no Spotify running (idle state, never launches Spotify itself).
- Idle CPU < 1%, no visible lag in animations.
