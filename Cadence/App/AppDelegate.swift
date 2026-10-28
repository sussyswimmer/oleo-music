import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let nowPlaying: NowPlayingStore
    let spotify: SpotifyService
    private let spotifyMonitor: SpotifyMonitor
    private let lockScreen: LockScreenController
    private let notch: NotchPanelController

    override init() {
        let settings = AppSettings()
        let nowPlaying = NowPlayingStore()
        let spotify = SpotifyService(store: nowPlaying)
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.spotify = spotify
        spotifyMonitor = SpotifyMonitor(service: spotify)
        lockScreen = LockScreenController(settings: settings, store: nowPlaying, spotify: spotify)
        notch = NotchPanelController(settings: settings, store: nowPlaying, spotify: spotify)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When the app only hosts unit tests, don't script Spotify or show any windows.
        guard !Self.isHostingTests else { return }
        Logger.app.info("Cadence launched")
        spotifyMonitor.start()
        lockScreen.start()
        notch.start()
    }

    private static var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
