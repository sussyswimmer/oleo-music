import AppKit
import Observation
import SwiftUI
import os

/// Brief 02 spike: on lock, shows a small card over the lock screen and records
/// what works (drawing, input, Spotify) to `LockScreenLog`.
///
/// Safety: the card never takes keyboard focus, tears itself down if a key
/// press ever reaches Cadence while locked, and is removed on any of three
/// unlock signals (two notifications and a session-state check).
@MainActor
final class LockScreenController: NSObject {
    /// Space levels the debug menu offers for testing.
    static let spikeLevels = [300, 400, 500]
    /// The card is centered horizontally, with its center this far up the screen.
    static let cardCenterHeightFraction = 0.45
    static let failSafeInterval: TimeInterval = 3

    private static let sessionLockedName = "com.apple.sessionagent.screenIsLocked"
    private static let sessionUnlockedName = "com.apple.sessionagent.screenIsUnlocked"

    private let settings: AppSettings
    private let store: NowPlayingStore
    private let spotify: SpotifyService
    private let log = LockScreenLog.shared
    private let model = LockScreenSpikeModel()
    private lazy var bridge = SkyLightBridge.load()

    private var window: NSWindow?
    private var space: SkyLightBridge.SpaceID?
    private var spacesCreated = 0
    private var failSafeTimer: Timer?
    /// The fail-safe only acts once the session dictionary has reported "locked",
    /// so a macOS that stopped reporting it can't tear the card down at once.
    private var sessionLockReported = false
    private var eventMonitor: Any?
    /// Diagnostics on/off updates, chained so they reach SpotifyService in order.
    private var diagnosticsUpdate: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastMouseMovedLog = Date.distantPast

    init(settings: AppSettings, store: NowPlayingStore, spotify: SpotifyService) {
        self.settings = settings
        self.store = store
        self.spotify = spotify
        super.init()
    }

    func start() {
        guard workspaceObservers.isEmpty else { return }

        // The notifications the brief names. Delivered immediately: AppKit holds
        // distributed notifications while an app is inactive.
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
        for event in PowerEvent.allCases {
            workspaceObservers.append(workspace.addObserver(forName: event.notification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.powerEvent(event) }
            })
        }

        observeEnabledSetting()
        log.write("Cadence started; lock screen player \(settings.lockScreenEnabled ? "on" : "off"), level \(settings.lockScreenSpaceLevel)")
    }

    // MARK: Lock and unlock

    @objc private nonisolated func distributedScreenLocked(_ notification: Notification) {
        Task { @MainActor in self.screenLocked(source: "distributed") }
    }

    @objc private nonisolated func distributedScreenUnlocked(_ notification: Notification) {
        Task { @MainActor in self.screenUnlocked(source: "distributed") }
    }

    private func screenLocked(source: String) {
        log.write("lock notification (\(source)); session locked: \(Self.sessionLockDescription())")
        guard settings.lockScreenEnabled else {
            log.write("lock screen player is off; not showing")
            return
        }
        // Each lock arrives twice (two notifications); the second one is a no-op.
        guard window == nil else { return }
        show()
    }

    private func screenUnlocked(source: String) {
        log.write("unlock notification (\(source))")
        teardown(reason: "unlock (\(source))")
    }

    private func show() {
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
        spacesCreated += 1
        model.reset(level: level)
        let window = makeWindow(on: screen)
        bridge.showSpace(created.id)
        let addResult = bridge.addWindow(window, to: created.id)
        window.orderFrontRegardless()
        self.window = window
        space = created.id
        sessionLockReported = Self.isSessionLocked() == true

        log.write("""
            shown: space \(created.id) level \(level) (set level result \(created.levelResult)), \
            add window result \(addResult), window \(window.windowNumber) at \(window.frame), \
            spaces created this run: \(spacesCreated)
            """)
        logStoreState()
        startFailSafe()
        installEventMonitor()
        setSpotifyDiagnostics(enabled: true)
    }

    private func teardown(reason: String) {
        failSafeTimer?.invalidate()
        failSafeTimer = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard let window else { return }
        window.orderOut(nil)
        window.close()
        self.window = nil
        if let space, case .success(let bridge) = bridge {
            bridge.hideSpace(space)
        }
        space = nil
        setSpotifyDiagnostics(enabled: false)
        log.write("torn down: \(reason)")
    }

    /// While locked, logs every Spotify script result, and refreshes once to test reading.
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

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let content = LockScreenSpikeView(store: store, spotify: spotify, model: model) { [log] action in
            log.write("button: \(action)")
        }
        let hostingView = FirstMouseHostingView(rootView: content)
        let size = hostingView.fittingSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * Self.cardCenterHeightFraction - size.height / 2,
            width: size.width,
            height: size.height
        )
        let panel = LockScreenPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hostingView
        panel.setFrame(frame, display: false)
        return panel
    }

    // MARK: Fail-safe

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
            log.write("fail-safe: session reports unlocked")
            teardown(reason: "fail-safe")
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

    // MARK: Input

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
            // Pass only the type across: NSEvent itself isn't Sendable.
            let type = event.type
            MainActor.assumeIsolated { self?.record(type) }
            return event
        }
    }

    private func record(_ type: NSEvent.EventType) {
        let name = Self.name(of: type)
        model.recordEvent(name)
        if type == .keyDown {
            // Key presses belong to the password field. If one reaches Cadence,
            // the card is in the way: get out immediately.
            log.write("input: keyDown reached Cadence; removing the card so the password field keeps focus")
            teardown(reason: "keyboard safety")
            return
        }
        if type == .mouseMoved {
            guard Date.now.timeIntervalSince(lastMouseMovedLog) > 1 else { return }
            lastMouseMovedLog = .now
        }
        log.write("input: \(name) (total \(model.inputCount))")
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

    private func logStoreState() {
        guard window != nil else { return }
        log.write("now playing: \(store.state), “\(store.track?.title ?? "no track")”, artwork \(store.artwork == nil ? "not loaded" : "loaded")")
        withObservationTracking {
            _ = (store.state, store.track, store.artwork)
        } onChange: { [weak self] in
            Task { @MainActor in self?.logStoreState() }
        }
    }

    private func observeEnabledSetting() {
        withObservationTracking {
            _ = settings.lockScreenEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !self.settings.lockScreenEnabled {
                    self.teardown(reason: "lock screen player turned off")
                }
                self.observeEnabledSetting()
            }
        }
    }

    private enum PowerEvent: CaseIterable {
        case willSleep, didWake, screensDidSleep, screensDidWake

        var notification: Notification.Name {
            switch self {
            case .willSleep: NSWorkspace.willSleepNotification
            case .didWake: NSWorkspace.didWakeNotification
            case .screensDidSleep: NSWorkspace.screensDidSleepNotification
            case .screensDidWake: NSWorkspace.screensDidWakeNotification
            }
        }
    }

    private func powerEvent(_ event: PowerEvent) {
        log.write("\(event); session locked: \(Self.sessionLockDescription())")
        // ARCHITECTURE.md: lock screen windows can vanish after sleep, so rebuild on wake.
        // Waking from full sleep posts didWake too; screensDidWake covers both cases once.
        if event == .screensDidWake, window != nil {
            teardown(reason: "rebuilding after \(event)")
            show()
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

/// Lets the first click on a non-key window press a button instead of only focusing it.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
