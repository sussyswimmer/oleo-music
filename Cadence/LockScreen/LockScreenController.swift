import AppKit
import Observation
import SwiftUI
import os

/// Shows the now-playing card over the lock screen.
///
/// While locked, the card is up whenever a track is playing or was paused less
/// than `pausedCardDuration` ago, and the display is awake. Each time it appears,
/// a fresh SkyLight space high enough to draw above the lock screen is created and
/// the card window moved into it; both are removed when it goes away.
///
/// Tapping the card's artwork opens full-screen art: the window grows to the
/// whole screen before the animation, and shrinks back after it closes. The
/// SwiftUI view always lays out on the full screen, offset inside the window.
///
/// Safety: the card never takes keyboard focus, and if a key press ever reaches
/// Cadence while locked it disappears until unlock. Four signals count as unlock:
/// two lock-state notifications, another regular app becoming active, and a
/// session-state check every few seconds while locked.
@MainActor
final class LockScreenController: NSObject {
    /// The card's center is this far up the screen, as a fraction of its height.
    static let cardCenterHeightFraction = 0.45
    /// A paused track stays on the lock screen this long, like on iPhone.
    static let pausedCardDuration: TimeInterval = 10 * 60
    static let failSafeInterval: TimeInterval = 3
    /// Space levels the debug menu offers.
    static let spaceLevels = [300, 400, 500]
    static let fullScreenAnimation = Animation.spring(response: 0.5, dampingFraction: 0.86)

    private static let sessionLockedName = "com.apple.sessionagent.screenIsLocked"
    private static let sessionUnlockedName = "com.apple.sessionagent.screenIsUnlocked"

    private let settings: AppSettings
    private let store: NowPlayingStore
    private let spotify: SpotifyService
    private let log = LockScreenLog.shared
    private let presentation = LockScreenPresentation()
    private lazy var bridge = SkyLightBridge.load()

    private var isLocked = false
    private var displayAwake = true
    /// A key press reached Cadence while locked: keep the card away until unlock.
    private var keyboardSafetyTripped = false
    /// The fail-safe only acts once the session has reported "locked" during this
    /// lock, so a macOS that stopped reporting it can't make it fire early.
    private var sessionLockReported = false
    private var window: NSWindow?
    private var hostingView: NSView?
    private var space: SkyLightBridge.SpaceID?
    /// Screen rects of the card and of the whole screen, for resizing the window.
    private var cardFrame: CGRect = .zero
    private var screenFrame: CGRect = .zero
    private var failSafeTimer: Timer?
    private var pauseExpiryTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Diagnostics on/off updates, chained so they reach SpotifyService in order.
    private var diagnosticsUpdate: Task<Void, Never>?
    private var lastMouseMovedLog = Date.distantPast

    init(settings: AppSettings, store: NowPlayingStore, spotify: SpotifyService) {
        self.settings = settings
        self.store = store
        self.spotify = spotify
        super.init()
    }

    func start() {
        guard workspaceObservers.isEmpty else { return }

        // Delivered immediately: AppKit holds distributed notifications while an app is inactive.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self, selector: #selector(distributedScreenLocked(_:)),
            name: .init("com.apple.screenIsLocked"), object: nil, suspensionBehavior: .deliverImmediately
        )
        distributed.addObserver(
            self, selector: #selector(distributedScreenUnlocked(_:)),
            name: .init("com.apple.screenIsUnlocked"), object: nil, suspensionBehavior: .deliverImmediately
        )

        // LivePaper (MIT) uses these Darwin notifications as the reliable signal on macOS 26.
        let darwin = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(darwin, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let controller = Unmanaged<LockScreenController>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in controller.screenLocked(source: "sessionagent") }
        }, Self.sessionLockedName as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(darwin, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let controller = Unmanaged<LockScreenController>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in controller.screenUnlocked(source: "sessionagent") }
        }, Self.sessionUnlockedName as CFString, nil, .deliverImmediately)

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayChanged(awake: false) }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayChanged(awake: true) }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isRegularApp = app?.activationPolicy == .regular
            let name = app?.bundleIdentifier ?? "an app"
            MainActor.assumeIsolated { self?.appActivated(name: name, isRegularApp: isRegularApp) }
        })

        observeNowPlaying()
        log.write("started; lock screen player \(settings.lockScreenEnabled ? "on" : "off"), level \(settings.lockScreenSpaceLevel), \(settings.lockScreenInteractive ? "interactive" : "display-only")")
    }

    // MARK: Lock state

    @objc private nonisolated func distributedScreenLocked(_ notification: Notification) {
        Task { @MainActor in self.screenLocked(source: "distributed") }
    }

    @objc private nonisolated func distributedScreenUnlocked(_ notification: Notification) {
        Task { @MainActor in self.screenUnlocked(source: "distributed") }
    }

    private func screenLocked(source: String) {
        // Each lock arrives from two sources; the second only re-checks the card.
        guard !isLocked else {
            updateCard()
            return
        }
        isLocked = true
        keyboardSafetyTripped = false
        sessionLockReported = Self.isSessionLocked() == true
        log.write("locked (\(source)); session reports locked: \(Self.sessionLockDescription())")
        startFailSafe()
        updateCard()
    }

    private func screenUnlocked(source: String) {
        guard isLocked else { return }
        isLocked = false
        log.write("unlocked (\(source))")
        failSafeTimer?.invalidate()
        failSafeTimer = nil
        pauseExpiryTask?.cancel()
        hideCard(reason: "unlock")
    }

    private func displayChanged(awake: Bool) {
        displayAwake = awake
        guard isLocked else { return }
        log.write("display \(awake ? "woke" : "slept")")
        // The card is rebuilt on wake: windows over the lock screen can vanish across sleep.
        updateCard()
    }

    private func appActivated(name: String, isRegularApp: Bool) {
        guard isLocked else { return }
        // Lock-screen processes aren't regular apps; a regular app coming forward
        // means the user is back in their session.
        if isRegularApp, name != Bundle.main.bundleIdentifier {
            screenUnlocked(source: "\(name) became active")
        } else if log.isEnabled {
            log.write("\(name) became active while locked (not a regular app; still locked)")
        }
    }

    // MARK: Card

    private var cardShouldShow: Bool {
        guard isLocked, displayAwake, !keyboardSafetyTripped, settings.lockScreenEnabled, store.track != nil else {
            return false
        }
        switch store.state {
        case .playing:
            return true
        case .paused:
            return store.pausedSince.map { Date.now.timeIntervalSince($0) < Self.pausedCardDuration } ?? false
        case .idle:
            return false
        }
    }

    private func updateCard() {
        if cardShouldShow {
            if window == nil {
                showCard()
            }
        } else if window != nil {
            hideCard(reason: "nothing to show")
        }
        schedulePauseExpiry()
    }

    /// Re-checks the card when a paused track's time on the lock screen runs out.
    private func schedulePauseExpiry() {
        pauseExpiryTask?.cancel()
        guard isLocked, store.state == .paused, let pausedSince = store.pausedSince else { return }
        let remaining = Self.pausedCardDuration - Date.now.timeIntervalSince(pausedSince)
        guard remaining > 0 else { return }
        pauseExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.updateCard()
        }
    }

    private func showCard() {
        let bridge: SkyLightBridge
        switch self.bridge {
        case .success(let loaded):
            bridge = loaded
        case .failure(let error):
            log.write("not showing: \(error)")
            return
        }
        guard let screen = NSScreen.screens.first else {
            log.write("not showing: no screen")
            return
        }
        let level = Int32(settings.lockScreenSpaceLevel)
        guard let created = bridge.createSpace(level: level) else {
            log.write("not showing: SLSSpaceCreate returned no space")
            return
        }

        let window = makeWindow(on: screen, interactive: settings.lockScreenInteractive)
        bridge.showSpace(created.id)
        let addResult = bridge.addWindow(window, to: created.id)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }
        self.window = window
        space = created.id
        installKeyboardSafety()
        setSpotifyDiagnostics(enabled: log.isEnabled)
        log.write("""
            card shown: space \(created.id) at level \(level) (result \(created.levelResult)), \
            window \(window.windowNumber) added (result \(addResult)) at \(window.frame)
            """)
    }

    private func hideCard(reason: String) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard let window else { return }
        window.orderOut(nil)
        window.close()
        self.window = nil
        hostingView = nil
        presentation.isFullScreen = false
        var destroyed = false
        if let space, case .success(let bridge) = bridge {
            bridge.hideSpace(space)
            destroyed = bridge.destroySpace(space)
        }
        space = nil
        setSpotifyDiagnostics(enabled: false)
        log.write("card removed (\(reason)); space \(destroyed ? "destroyed" : "hidden")")
    }

    private func makeWindow(on screen: NSScreen, interactive: Bool) -> NSWindow {
        let measured = NSHostingView(rootView: LockScreenCard(
            store: store, spotify: spotify, interactive: interactive, artworkNamespace: nil, onArtworkTap: {}
        ))
        screenFrame = screen.frame
        cardFrame = Self.cardFrame(size: measured.fittingSize, on: screen.frame)
        presentation.isFullScreen = false
        presentation.canvasSize = screen.frame.size
        presentation.cardRect = CGRect(
            x: cardFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - cardFrame.maxY,
            width: cardFrame.width,
            height: cardFrame.height
        )

        let content = LockScreenView(
            store: store,
            spotify: spotify,
            presentation: presentation,
            interactive: interactive,
            onArtworkTap: { [weak self] in self?.openFullScreen() },
            onFullScreenTap: { [weak self] in self?.closeFullScreen() }
        )
        let hostingView = FirstMouseHostingView(rootView: content)
        // The window size is managed here, not derived from the SwiftUI content.
        hostingView.sizingOptions = []
        let container = NSView()
        container.addSubview(hostingView)

        let panel = LockScreenPanel(contentRect: cardFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = container
        // Display-only: clicks go straight through to the lock screen.
        panel.ignoresMouseEvents = !interactive
        self.hostingView = hostingView
        applyWindowFrame(cardFrame, to: panel)
        return panel
    }

    /// The card's screen rect: centered horizontally, `cardCenterHeightFraction` up the screen.
    static func cardFrame(size: CGSize, on screen: CGRect) -> CGRect {
        CGRect(
            x: screen.midX - size.width / 2,
            y: screen.minY + screen.height * cardCenterHeightFraction - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Resizes the window without moving the content on screen.
    private func applyWindowFrame(_ frame: CGRect, to window: NSWindow) {
        hostingView?.frame = CGRect(
            x: screenFrame.minX - frame.minX,
            y: screenFrame.minY - frame.minY,
            width: screenFrame.width,
            height: screenFrame.height
        )
        window.setFrame(frame, display: true)
    }

    // MARK: Full-screen art

    private func openFullScreen() {
        guard settings.fullScreenArtEnabled, settings.lockScreenInteractive, let window, !presentation.isFullScreen else { return }
        log.write("full-screen art opened")
        applyWindowFrame(screenFrame, to: window)
        withAnimation(Self.fullScreenAnimation) {
            presentation.isFullScreen = true
        }
    }

    private func closeFullScreen() {
        guard presentation.isFullScreen else { return }
        log.write("full-screen art closed")
        withAnimation(Self.fullScreenAnimation) {
            presentation.isFullScreen = false
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                // Shrink only if it wasn't reopened or removed meanwhile.
                guard let self, !self.presentation.isFullScreen, let window = self.window else { return }
                self.applyWindowFrame(self.cardFrame, to: window)
            }
        }
    }

    // MARK: Safety

    private func startFailSafe() {
        failSafeTimer?.invalidate()
        let timer = Timer(timeInterval: Self.failSafeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSessionStillLocked() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        failSafeTimer = timer
    }

    private func checkSessionStillLocked() {
        switch Self.isSessionLocked() {
        case true?:
            sessionLockReported = true
        case false? where sessionLockReported:
            screenUnlocked(source: "fail-safe: session reports unlocked")
        default:
            break
        }
    }

    /// From the public `CGSessionCopyCurrentDictionary`; nil if there's no session info.
    nonisolated static func isSessionLocked() -> Bool? {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return info["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static func sessionLockDescription() -> String {
        switch isSessionLocked() {
        case true?: "yes"
        case false?: "no"
        case nil: "unknown"
        }
    }

    /// Key presses belong to the password field. If one reaches Cadence, the card
    /// is in the way: remove it until unlock. Also logs input in diagnostics builds.
    private func installKeyboardSafety() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
            // Pass only the type across: NSEvent itself isn't Sendable.
            let type = event.type
            MainActor.assumeIsolated { self?.received(type) }
            return event
        }
    }

    private func received(_ type: NSEvent.EventType) {
        if type == .keyDown {
            keyboardSafetyTripped = true
            log.write("input: keyDown reached Cadence; removing the card until unlock")
            hideCard(reason: "keyboard safety")
            return
        }
        guard log.isEnabled else { return }
        if type == .mouseMoved {
            guard Date.now.timeIntervalSince(lastMouseMovedLog) > 1 else { return }
            lastMouseMovedLog = .now
        }
        log.write("input: \(Self.name(of: type))")
    }

    private static func name(of type: NSEvent.EventType) -> String {
        switch type {
        case .leftMouseDown: "leftMouseDown"
        case .leftMouseUp: "leftMouseUp"
        case .leftMouseDragged: "leftMouseDragged"
        case .rightMouseDown: "rightMouseDown"
        case .rightMouseUp: "rightMouseUp"
        case .mouseMoved: "mouseMoved"
        case .mouseEntered: "mouseEntered"
        case .mouseExited: "mouseExited"
        case .scrollWheel: "scrollWheel"
        case .keyDown: "keyDown"
        case .keyUp: "keyUp"
        case .flagsChanged: "flagsChanged"
        default: "event type \(type.rawValue)"
        }
    }

    // MARK: Observation

    private func observeNowPlaying() {
        withObservationTracking {
            _ = (store.state, store.track?.id, store.pausedSince, store.artwork, settings.lockScreenEnabled)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.isLocked, self.log.isEnabled {
                    self.log.write("now playing: \(self.store.state), “\(self.store.track?.title ?? "no track")”, artwork \(self.store.artwork == nil ? "not loaded" : "loaded")")
                }
                self.updateCard()
                self.observeNowPlaying()
            }
        }
    }

    /// While the card is up in a diagnostics build, logs every Spotify script result
    /// and refreshes once, to see whether Spotify answers while locked.
    private func setSpotifyDiagnostics(enabled: Bool) {
        let previous = diagnosticsUpdate
        var handler: (@Sendable (String) -> Void)?
        if enabled {
            handler = { [log] line in log.write("spotify: \(line)") }
        }
        diagnosticsUpdate = Task { [spotify, handler] in
            await previous?.value
            await spotify.setDiagnostics(handler)
            if enabled {
                await spotify.refresh()
            }
        }
    }
}

/// The lock screen window: borderless, transparent, and never key, so the
/// password field always keeps the keyboard.
private final class LockScreenPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Panels hide when their app is inactive, and Cadence always is.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        canBecomeVisibleWithoutLogin = true
        level = .screenSaver
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
