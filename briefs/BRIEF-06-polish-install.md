# Brief 06 — Polish, resilience, install

## Goal
Make it feel finished and safe to leave running all day on my Mac.

## Tasks
1. **App icon**: simple original icon (not Oleo's). Generate all sizes.
2. **Settings window** (SwiftUI): toggles for notch player, lock screen player, full-screen art, launch at login; hover delay slider; optional "dim art when paused".
3. **First-run experience**: if Automation permission to Spotify is missing/denied, show a friendly state in the menu bar menu with a button that opens System Settings → Privacy & Security → Automation.
4. **Resilience pass**:
   - Spotify crashes/relaunches mid-song.
   - Display hot-plug, lid close/open, sleep/wake, fast user switching.
   - Rapid track skipping (debounce UI updates, no stale artwork).
   - Network offline (artwork fails → placeholder, no retry storm).
   - Very long titles (marquee or truncate gracefully).
5. **Performance pass**: Instruments (Time Profiler + energy). Idle < 1% CPU, no timers running when nothing plays or the screen is off.
6. **Private API safety**: feature flag + runtime check; if SkyLight symbols are missing after a macOS update, disable lock screen features and show a one-line note in the menu.
7. **Install**: Release build archived locally, copy `Cadence.app` to `/Applications`, add to Login Items. Write `INSTALL.md` with: build steps, the Automation permission step, how to re-trust after macOS updates, how to disable the lock screen feature if an update breaks it, how to uninstall.
8. **Update procedure**: document in `INSTALL.md` how to rebuild and replace after changes.

## Acceptance criteria
- A 1-hour soak test with normal use: no memory growth (check in Activity Monitor), no crashes, no stuck windows.
- Fresh-user simulation (reset TCC with `tccutil reset AppleEvents com.maxwell.cadence`) shows the friendly permission flow.
- All settings take effect immediately without relaunch.
- `INSTALL.md` is accurate (follow it from scratch and confirm).

## Report back
Soak test results, Instruments summary, any remaining known issues.
