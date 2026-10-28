import AppKit
import Observation
import SwiftUI
import os

/// The notch player window: album art beside the notch while Spotify plays, and
/// a full player growing down from the notch on hover.
///
/// The window is only as large as it needs to be. Collapsed, it covers the art
/// chip and the notch, so the rest of the menu bar stays clickable. On hover it
/// grows to the full canvas before the expand animation starts, and shrinks back
/// once the collapse animation ends. The SwiftUI view always lays out on the
/// full canvas and is offset inside the window, so resizing never moves it.
@MainActor
final class NotchPanelController {
    static let openDelay = Duration.milliseconds(120)
    static let closeDelay = Duration.milliseconds(250)
    static let expandAnimation = Animation.spring(response: 0.38, dampingFraction: 0.82)

    private let settings: AppSettings
    private let store: NowPlayingStore
    private let spotify: SpotifyService
    private let state = NotchPanelState()
    private var panel: NSPanel?
    private var hostingView: NSView?
    private var frames: NotchGeometry.Frames?
    private var hoverTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    init(settings: AppSettings, store: NowPlayingStore, spotify: SpotifyService) {
        self.settings = settings
        self.store = store
        self.spotify = spotify
    }

    func start() {
        guard screenObserver == nil else { return }
        // Displays plugged in or removed, resolution changes, the lid opening or closing.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutForCurrentScreen() }
        }
        layoutForCurrentScreen()
        observeVisibility()
    }

    // MARK: Layout

    private func layoutForCurrentScreen() {
        guard let geometry = NotchGeometry.current() else {
            frames = nil
            panel?.orderOut(nil)
            Logger.notch.error("No screen for the notch player")
            return
        }
        let frames = geometry.frames()
        self.frames = frames
        state.update(geometry: geometry, frames: frames)
        if panel == nil {
            panel = makePanel()
        }
        applyFrame(state.isExpanded ? frames.canvas : frames.collapsed)
        updateVisibility()
        Logger.notch.info("Notch at \(String(describing: geometry.notchRect), privacy: .public), hardware notch: \(geometry.hasHardwareNotch ? "yes" : "no", privacy: .public)")
    }

    private func makePanel() -> NSPanel {
        let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let container = HoverTrackingView()
        container.onHoverChange = { [weak self] inside in
            self?.hoverChanged(inside)
        }
        let hostingView = FirstMouseHostingView(rootView: NotchView(store: store, spotify: spotify, state: state))
        // The window size is managed here, not derived from the SwiftUI content.
        hostingView.sizingOptions = []
        container.addSubview(hostingView)
        panel.contentView = container
        self.hostingView = hostingView
        return panel
    }

    /// Resizes the window without moving the content on screen.
    private func applyFrame(_ frame: CGRect) {
        guard let panel, let hostingView, let frames else { return }
        // Reposition the content first so the resize and its redraw land together.
        hostingView.frame = CGRect(
            x: frames.canvas.minX - frame.minX,
            y: frames.canvas.minY - frame.minY,
            width: frames.canvas.width,
            height: frames.canvas.height
        )
        panel.setFrame(frame, display: true)
    }

    // MARK: Visibility

    private var shouldShow: Bool {
        settings.notchEnabled && store.state != .idle && store.track != nil && frames != nil
    }

    private func updateVisibility() {
        guard let panel, let frames else { return }
        if shouldShow {
            guard !panel.isVisible else { return }
            state.isExpanded = false
            applyFrame(frames.collapsed)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
        } else if panel.isVisible {
            hoverTask?.cancel()
            state.isExpanded = false
            panel.orderOut(nil)
        }
    }

    private func observeVisibility() {
        withObservationTracking {
            _ = (settings.notchEnabled, store.state, store.track?.id)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateVisibility()
                self?.observeVisibility()
            }
        }
    }

    // MARK: Hover

    private func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        hoverTask = Task {
            // Short delays so brushing past the notch doesn't flicker it open and shut.
            try? await Task.sleep(for: inside ? Self.openDelay : Self.closeDelay)
            guard !Task.isCancelled else { return }
            if inside {
                expand()
            } else {
                collapse()
            }
        }
    }

    private func expand() {
        guard let frames, let panel, panel.isVisible, !state.isExpanded else { return }
        applyFrame(frames.canvas)
        withAnimation(Self.expandAnimation) {
            state.isExpanded = true
        }
        // The pointer may have left during the open delay.
        if !frames.canvas.contains(NSEvent.mouseLocation) {
            hoverChanged(false)
        }
    }

    private func collapse() {
        guard state.isExpanded else { return }
        withAnimation(Self.expandAnimation) {
            state.isExpanded = false
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                // Shrink the window only if nothing re-expanded it meanwhile.
                guard let self, !self.state.isExpanded, let frames = self.frames else { return }
                self.applyFrame(frames.collapsed)
            }
        }
    }
}

/// Borderless, transparent, never key: clicking the player doesn't take focus
/// from the app you're using.
private final class NotchPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Panels hide when their app is inactive, and Cadence always is.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        // Above the menu bar, on every Space and over full-screen apps.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Reports the pointer entering and leaving the whole window.
private final class HoverTrackingView: NSView {
    var onHoverChange: (@MainActor (Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        // activeAlways: Cadence is never the active app.
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
