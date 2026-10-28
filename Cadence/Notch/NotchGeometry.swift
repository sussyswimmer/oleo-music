import AppKit

/// Where the notch and the menu bar beside it are, in global screen coordinates
/// (origin at the bottom left of the primary display, y up).
struct NotchGeometry: Equatable, Sendable {
    let screenFrame: CGRect
    /// The camera housing, or a virtual notch on screens without one.
    let notchRect: CGRect
    /// The menu-bar band to the left and right of the notch.
    let leftArea: CGRect
    let rightArea: CGRect
    /// False when `notchRect` is the virtual notch of the no-notch fallback.
    let hasHardwareNotch: Bool

    /// Height of the menu-bar band, which is also the notch height.
    var bandHeight: CGFloat { notchRect.height }

    /// From a notched screen's measurements: the top safe-area inset and the widths
    /// of `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Only the widths
    /// are used, so it doesn't matter which coordinate space those rects are in.
    /// Nil if the screen has no notch.
    init?(screenFrame: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?) {
        guard safeAreaTop > 0, let leftAreaWidth, let rightAreaWidth else { return nil }
        let notchWidth = screenFrame.width - leftAreaWidth - rightAreaWidth
        guard notchWidth > 0 else { return nil }
        let y = screenFrame.maxY - safeAreaTop
        self.screenFrame = screenFrame
        notchRect = CGRect(x: screenFrame.minX + leftAreaWidth, y: y, width: notchWidth, height: safeAreaTop)
        leftArea = CGRect(x: screenFrame.minX, y: y, width: leftAreaWidth, height: safeAreaTop)
        rightArea = CGRect(x: screenFrame.maxX - rightAreaWidth, y: y, width: rightAreaWidth, height: safeAreaTop)
        hasHardwareNotch = true
    }

    /// For a screen without a notch: a virtual notch centered in the menu bar.
    init(fallbackFor screenFrame: CGRect, menuBarHeight: CGFloat, notchWidth: CGFloat = 180) {
        let y = screenFrame.maxY - menuBarHeight
        let x = screenFrame.midX - notchWidth / 2
        self.screenFrame = screenFrame
        notchRect = CGRect(x: x, y: y, width: notchWidth, height: menuBarHeight)
        leftArea = CGRect(x: screenFrame.minX, y: y, width: x - screenFrame.minX, height: menuBarHeight)
        rightArea = CGRect(x: x + notchWidth, y: y, width: screenFrame.maxX - x - notchWidth, height: menuBarHeight)
        hasHardwareNotch = false
    }
}

/// Sizes for the notch player. Points.
struct NotchLayout: Equatable, Sendable {
    /// Black padding left of the art chip.
    var chipInset: CGFloat = 6
    /// Space between the art chip and the notch.
    var chipGap: CGFloat = 8
    /// The chip is the band height minus this, top and bottom.
    var chipVerticalInset: CGFloat = 4
    var expandedWidth: CGFloat = 380
    /// Height of the expanded player below the menu-bar band.
    var expandedContentHeight: CGFloat = 170
    /// Room for the expanded panel's shadow.
    var shadowMargin: CGFloat = 16
    var collapsedCornerRadius: CGFloat = 10
    var expandedCornerRadius: CGFloat = 24

    static let standard = NotchLayout()
}

extension NotchGeometry {
    /// Screen rects for the notch player.
    struct Frames: Equatable, Sendable {
        /// The panel while collapsed: the chip and the notch, nothing to the notch's right.
        let collapsed: CGRect
        let chip: CGRect
        /// The black expanded player, attached to the top of the screen.
        let expandedPanel: CGRect
        /// The panel window while expanded: the player plus its shadow margin. Also the
        /// canvas the SwiftUI view always lays out in.
        let canvas: CGRect
    }

    func frames(for layout: NotchLayout = .standard) -> Frames {
        let chipSize = bandHeight - 2 * layout.chipVerticalInset
        let chip = CGRect(
            x: notchRect.minX - layout.chipGap - chipSize,
            y: notchRect.minY + layout.chipVerticalInset,
            width: chipSize,
            height: chipSize
        )
        let collapsedMinX = chip.minX - layout.chipInset
        let collapsed = CGRect(x: collapsedMinX, y: notchRect.minY, width: notchRect.maxX - collapsedMinX, height: bandHeight)

        // Centered on the notch and wide enough to cover the collapsed shape, so one grows into the other.
        let panelWidth = max(layout.expandedWidth, 2 * (notchRect.midX - collapsedMinX))
        let panelHeight = bandHeight + layout.expandedContentHeight
        let expandedPanel = CGRect(
            x: notchRect.midX - panelWidth / 2,
            y: screenFrame.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )
        let canvas = CGRect(
            x: expandedPanel.minX - layout.shadowMargin,
            y: expandedPanel.minY - layout.shadowMargin,
            width: expandedPanel.width + 2 * layout.shadowMargin,
            height: expandedPanel.height + layout.shadowMargin
        ).intersection(screenFrame)

        return Frames(collapsed: collapsed, chip: chip, expandedPanel: expandedPanel, canvas: canvas)
    }

    /// `rect` in SwiftUI coordinates inside `canvas`: origin at the canvas's top left, y down.
    static func local(_ rect: CGRect, in canvas: CGRect) -> CGRect {
        CGRect(x: rect.minX - canvas.minX, y: canvas.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: NSScreen

extension NotchGeometry {
    /// The built-in notched screen if there is one, otherwise a virtual notch on the main screen.
    @MainActor
    static func current() -> NotchGeometry? {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
           let geometry = NotchGeometry(
               screenFrame: screen.frame,
               safeAreaTop: screen.safeAreaInsets.top,
               leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
               rightAreaWidth: screen.auxiliaryTopRightArea?.width
           ) {
            return geometry
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        // With an auto-hiding menu bar the visible frame reaches the top; use the standard height then.
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        return NotchGeometry(fallbackFor: screen.frame, menuBarHeight: menuBarHeight)
    }
}
