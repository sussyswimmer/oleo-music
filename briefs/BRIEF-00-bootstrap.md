# Brief 00 — Bootstrap

## Goal
A compiling macOS 26 menu-bar app skeleton with the right project settings, folder layout, and a menu bar item. No features yet.

## Read first
`CLAUDE.md`, `README.md`, `ARCHITECTURE.md`.

## Tasks
1. Create a new Xcode macOS app project named **Cadence** (SwiftUI lifecycle, Swift 6), bundle ID `com.maxwell.cadence`, deployment target macOS 26.0. Commit a `.gitignore` for Xcode/Swift.
2. Project settings:
   - `LSUIElement = YES` (no Dock icon).
   - App Sandbox **off**. Remove sandbox entitlements.
   - Add `NSAppleEventsUsageDescription` = "Cadence reads and controls Spotify to show what's playing."
   - Signing: "Sign to Run Locally".
3. Create the folder/group layout from `CLAUDE.md` (empty placeholder files are fine).
4. Implement `MenuBarExtra` with a music-note SF Symbol and items: "Show notch player" (toggle, disabled for now), "Lock screen player" (toggle, disabled for now), "Launch at login" (working, via `SMAppService.mainApp`), "Quit".
5. Add `AppSettings` (`@AppStorage` wrapper) for: `notchEnabled`, `lockScreenEnabled`, `launchAtLogin`.
6. Add a `Logger` helper (`os.Logger`, subsystem `com.maxwell.cadence`) with categories: `spotify`, `notch`, `lockscreen`.

## Acceptance criteria
- `xcodebuild -scheme Cadence -destination 'platform=macOS' build` succeeds with no warnings.
- Running the app shows a menu bar icon and **no Dock icon**.
- "Launch at login" toggle registers/unregisters correctly (verify in System Settings → General → Login Items).
- Quit works.

## Do not
- Add any Swift packages.
- Start on notch or Spotify code.

## Report back
List of files created, any Xcode 26 quirks hit, and the exact build command used.
