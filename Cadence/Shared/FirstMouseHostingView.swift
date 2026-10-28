import SwiftUI

/// Hosts SwiftUI in a window that never becomes key, and lets the first click
/// press a button instead of only bringing the window forward.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
