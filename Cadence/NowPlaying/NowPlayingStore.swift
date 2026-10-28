import AppKit
import Observation

/// The single source of truth for what Spotify is playing. `SpotifyService`
/// writes to it; every UI reads from it.
@Observable
@MainActor
final class NowPlayingStore {
    /// The playback position at a known moment. While playing, the UI
    /// extrapolates from it instead of asking Spotify again.
    struct PositionAnchor: Equatable {
        var seconds: Double
        var date: Date
    }

    private(set) var state: PlaybackState = .idle
    private(set) var track: Track?
    /// Artwork for `track`. The previous image stays until the new one has loaded.
    private(set) var artwork: NSImage?
    private(set) var positionAnchor = PositionAnchor(seconds: 0, date: .distantPast)
    /// macOS blocked Cadence from controlling Spotify (Automation permission denied).
    private(set) var automationDenied = false

    @ObservationIgnored private let artworkLoader: ArtworkLoader
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var lastReadAt = Date.distantPast

    init(artworkLoader: ArtworkLoader = ArtworkLoader()) {
        self.artworkLoader = artworkLoader
    }

    /// The position at `date`: extrapolated while playing, never past the end of the track.
    func currentPosition(at date: Date = .now) -> Double {
        var seconds = positionAnchor.seconds
        if state == .playing {
            seconds += max(0, date.timeIntervalSince(positionAnchor.date))
        }
        if let duration = track?.durationSeconds, duration > 0 {
            seconds = min(seconds, duration)
        }
        return seconds
    }

    func apply(_ snapshot: SpotifySnapshot) {
        // Refreshes can finish out of order; never let an older reading win.
        guard snapshot.readAt >= lastReadAt else { return }
        lastReadAt = snapshot.readAt

        if snapshot.track?.artworkURL != track?.artworkURL {
            loadArtwork(from: snapshot.track?.artworkURL)
        }
        state = snapshot.state
        track = snapshot.track
        positionAnchor = PositionAnchor(seconds: snapshot.positionSeconds, date: snapshot.readAt)
    }

    func setAutomationDenied(_ denied: Bool) {
        automationDenied = denied
    }

    private func loadArtwork(from url: URL?) {
        artworkTask?.cancel()
        guard let url else {
            artworkTask = nil
            artwork = nil
            return
        }
        artworkTask = Task {
            let image = await artworkLoader.image(for: url)
            // A newer track replaced this one while it loaded.
            guard !Task.isCancelled else { return }
            artwork = image
        }
    }
}
