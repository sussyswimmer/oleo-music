import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let nowPlaying: NowPlayingStore
    let spotify: SpotifyService
    private let spotifyMonitor: SpotifyMonitor

    override init() {
        let nowPlaying = NowPlayingStore()
        let spotify = SpotifyService(store: nowPlaying)
        self.nowPlaying = nowPlaying
        self.spotify = spotify
        spotifyMonitor = SpotifyMonitor(service: spotify)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("Cadence launched")
        spotifyMonitor.start()
    }
}
