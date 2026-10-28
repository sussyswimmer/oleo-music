import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let nowPlaying: NowPlayingStore
    let spotify: SpotifyService
    private let spotifyMonitor: SpotifyMonitor
    private let lockScreen: LockScreenController

    override init() {
        let settings = AppSettings()
        let nowPlaying = NowPlayingStore()
        let spotify = SpotifyService(store: nowPlaying)
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.spotify = spotify
        spotifyMonitor = SpotifyMonitor(service: spotify)
        lockScreen = LockScreenController(settings: settings, store: nowPlaying, spotify: spotify)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("Cadence launched")
        spotifyMonitor.start()
        lockScreen.start()
    }
}
