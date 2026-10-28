import Foundation
import Testing
@testable import Cadence

/// Fake screens. The notch widths are close to real 14" and 16" MacBook Pros.
private let macBookPro14 = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let macBookPro16 = CGRect(x: 0, y: 0, width: 1728, height: 1117)

struct NotchGeometryTests {
    @Test func notchOnPrimaryScreen() throws {
        let geometry = try #require(NotchGeometry(screenFrame: macBookPro14, safeAreaTop: 32, leftAreaWidth: 664, rightAreaWidth: 664))
        #expect(geometry.notchRect == CGRect(x: 664, y: 950, width: 184, height: 32))
        #expect(geometry.leftArea == CGRect(x: 0, y: 950, width: 664, height: 32))
        #expect(geometry.rightArea == CGRect(x: 848, y: 950, width: 664, height: 32))
        #expect(geometry.bandHeight == 32)
        #expect(geometry.hasHardwareNotch)
    }

    @Test func unevenMenuBarAreas() throws {
        let geometry = try #require(NotchGeometry(screenFrame: macBookPro16, safeAreaTop: 38, leftAreaWidth: 760, rightAreaWidth: 768))
        #expect(geometry.notchRect == CGRect(x: 760, y: 1079, width: 200, height: 38))
        #expect(geometry.rightArea.minX == geometry.notchRect.maxX)
        #expect(geometry.rightArea.maxX == macBookPro16.maxX)
    }

    @Test func notchOnSecondaryScreen() throws {
        // Built-in display arranged left of and below an external primary display.
        let frame = CGRect(x: -1512, y: -982, width: 1512, height: 982)
        let geometry = try #require(NotchGeometry(screenFrame: frame, safeAreaTop: 32, leftAreaWidth: 664, rightAreaWidth: 664))
        #expect(geometry.notchRect == CGRect(x: -848, y: -32, width: 184, height: 32))
        #expect(geometry.leftArea.minX == -1512)
    }

    @Test(arguments: [
        (CGFloat(0), CGFloat?(664), CGFloat?(664)),
        (32, nil, 664),
        (32, 664, nil),
        (32, 800, 800),
    ])
    func noNotch(safeAreaTop: CGFloat, left: CGFloat?, right: CGFloat?) {
        #expect(NotchGeometry(screenFrame: macBookPro14, safeAreaTop: safeAreaTop, leftAreaWidth: left, rightAreaWidth: right) == nil)
    }

    @Test func fallbackPillIsCentered() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry(fallbackFor: screen, menuBarHeight: 24)
        #expect(geometry.notchRect == CGRect(x: 1190, y: 1416, width: 180, height: 24))
        #expect(geometry.leftArea.width + geometry.notchRect.width + geometry.rightArea.width == screen.width)
        #expect(!geometry.hasHardwareNotch)
    }

    @Test func collapsedFrameNeverReachesRightOfTheNotch() throws {
        let geometry = try #require(NotchGeometry(screenFrame: macBookPro14, safeAreaTop: 32, leftAreaWidth: 664, rightAreaWidth: 664))
        let frames = geometry.frames(for: .standard)
        // Menu bar items right of the notch (clock, Control Center) stay clickable.
        #expect(frames.collapsed.maxX == geometry.notchRect.maxX)
        #expect(frames.collapsed.minY == geometry.notchRect.minY)
        #expect(frames.collapsed.height == geometry.bandHeight)
        // Chip: square, vertically centered in the band, just left of the notch.
        #expect(frames.chip.width == 24 && frames.chip.height == 24)
        #expect(frames.chip.midY == geometry.notchRect.midY)
        #expect(frames.chip.maxX == geometry.notchRect.minX - NotchLayout.standard.chipGap)
        #expect(frames.collapsed.minX == frames.chip.minX - NotchLayout.standard.chipInset)
    }

    @Test func expandedFrameContainsCollapsedAndStaysOnScreen() throws {
        for (screen, top, side) in [(macBookPro14, CGFloat(32), CGFloat(664)), (macBookPro16, 38, 764)] {
            let geometry = try #require(NotchGeometry(screenFrame: screen, safeAreaTop: top, leftAreaWidth: side, rightAreaWidth: side))
            let frames = geometry.frames(for: .standard)
            #expect(frames.expandedPanel.contains(frames.collapsed))
            #expect(frames.canvas.contains(frames.expandedPanel))
            #expect(screen.contains(frames.canvas))
            #expect(frames.expandedPanel.maxY == screen.maxY)
            #expect(frames.expandedPanel.midX == geometry.notchRect.midX)
            #expect(frames.expandedPanel.height == top + NotchLayout.standard.expandedContentHeight)
        }
    }

    @Test func localCoordinatesAreTopLeftOrigin() {
        let canvas = CGRect(x: 100, y: 500, width: 400, height: 200)
        #expect(NotchGeometry.local(CGRect(x: 100, y: 690, width: 10, height: 10), in: canvas) == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(NotchGeometry.local(CGRect(x: 150, y: 500, width: 20, height: 30), in: canvas) == CGRect(x: 50, y: 170, width: 20, height: 30))
    }
}
