# Brief 07 — Synced lyrics (LATER, not v1)

## Goal
Add a lyrics button to the notch player and lock screen that scrolls lyrics in time with the song, ideally lighting up word by word (karaoke style).

## Not started until
v1 (Briefs 00–06) is stable.

## Research first (do this before writing code, and report options)
1. **Line-synced lyrics source (free):** LRCLIB (lrclib.net) is a free, keyless lyrics API that returns synced LRC. Verify the current endpoints and terms (a lookup by track name, artist, album, duration is expected; also a search endpoint). Test coverage against 20 songs I actually listen to (I will provide a list) and report the hit rate.
2. **Word-level timing:** line-synced LRC only has a timestamp per line. Options to compare:
   - Interpolate word timing within each line (weighted by syllable/character count): free, decent, never perfect.
   - Find a free source that provides word-level timestamps ("enhanced LRC" or similar) and check its license/terms.
   - Skip word-level, ship smooth line-level highlighting with a soft sweep.
   Recommend one, with a demo on 3 songs.
3. **Legal/terms:** note any terms of the chosen API; this stays personal and cached locally.

## Likely implementation (after approval)
- `LyricsService` (actor): fetch by title/artist/album/duration, parse LRC, cache on disk by Spotify track ID, handle misses silently.
- `LyricsView`: auto-scrolling list, active line emphasized, inactive lines blurred/dimmed, per-word fill animation driven by `NowPlayingStore.currentPosition`. Respect scrubbing and pauses.
- Offset setting (±) to fix systematic sync drift per song.
- Toggle button in the expanded notch and lock screen card.

## Acceptance criteria (for the eventual build)
- Lyrics for a found song stay within ~200 ms of the audio, including after seeking.
- No network calls for songs already cached.
- Missing lyrics show a quiet "No lyrics" state, never an error dialog.

## Report back (for the research phase)
Hit rate, the recommended word-timing approach, and a go/no-go.
