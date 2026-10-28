import Foundation

struct Track: Identifiable, Equatable, Sendable {
    /// Spotify URI, e.g. `spotify:track:…`.
    let id: String
    let title: String
    let artist: String
    let album: String
    let durationSeconds: Double
    let artworkURL: URL?
}

enum PlaybackState: Equatable, Sendable {
    /// Spotify isn't running, or nothing is loaded.
    case idle
    case paused
    case playing
}
