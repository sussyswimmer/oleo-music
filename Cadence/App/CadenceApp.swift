import SwiftUI

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cadence", systemImage: "music.note") {
            MenuBarContent(settings: appDelegate.settings)
        }

        #if DEBUG
        Window("Now Playing (Debug)", id: DebugNowPlayingView.windowID) {
            DebugNowPlayingView(store: appDelegate.nowPlaying, spotify: appDelegate.spotify)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }
}
