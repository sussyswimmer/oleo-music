# Brief 05 — Full-screen album art + ambient background + big clock

## Goal
Tap the artwork on the lock screen player and it expands into a full-screen view: huge cover, ambient animated background taken from the album colors, and a big clock. Tap again (or press a key) to collapse.

## Preconditions
Brief 04 done, and Brief 02 found that clicks reach the lock screen window. If clicks do **not** work, propose an alternative trigger (e.g. auto-expand after N seconds of lock, or a setting "always full-screen when locked") and wait for my answer before building.

## Read first
`ARCHITECTURE.md` → "Full-screen art".

## Tasks
1. `PaletteExtractor`: downsample artwork (~32×32), cluster to 3–5 colors, discard near-black/near-white/dull colors, return sorted vibrant colors with a fallback palette for monochrome covers. Pure function, unit-tested with synthetic images.
2. `AmbientBackground`: SwiftUI `MeshGradient` using the palette, slow drift animation, plus blur and a slight dark overlay for text legibility. Cross-fade over ~1 s on track change.
3. `FullScreenArtView`: very large rounded cover (~50–60% of screen height) with soft shadow, title and artist under it, minimal progress bar, big clock (large thin font) — arrange so clock and cover don't fight; try clock above cover.
4. Expand/collapse transition from the lock screen card (matched geometry or scale+fade; keep it 60 fps).
5. Keep it cheap: pause the mesh animation if nothing is playing, and lower frame rate when paused.
6. Setting: `fullScreenArtEnabled` (default on).

## Acceptance criteria
- Tap artwork on lock screen → smooth expansion; tap again collapses.
- Background colors visibly match the cover; track change cross-fades; monochrome/black covers still look good (fallback palette).
- Clock correct and updates every second (or minute if seconds hidden).
- Text always legible on bright and dark covers.
- GPU/CPU stays modest while locked (check Activity Monitor: < 10% GPU on Apple silicon).
- Unlock removes everything cleanly.

## Do not
- Use Screen Recording to grab the wallpaper.
- Block unlocking or keyboard entry for the password.

## Report back
Palette approach details, performance numbers, any visual issues on bright covers.
