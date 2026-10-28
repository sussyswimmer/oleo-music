import AppKit
import os

/// Downloads album artwork and keeps the most recently used images in memory.
@MainActor
final class ArtworkLoader {
    private let session: URLSession
    private let capacity: Int
    private var cache: [URL: NSImage] = [:]
    /// Cached URLs, least recently used first.
    private var recentURLs: [URL] = []

    init(session: URLSession = .shared, capacity: Int = 16) {
        self.session = session
        self.capacity = capacity
    }

    /// The image at `url`, or nil if it couldn't be downloaded or decoded.
    func image(for url: URL) async -> NSImage? {
        if let cached = cache[url] {
            markRecentlyUsed(url)
            return cached
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else {
                Logger.spotify.error("Artwork download failed: bad response for \(url.absoluteString, privacy: .public)")
                return nil
            }
            insert(image, for: url)
            return image
        } catch {
            if (error as? URLError)?.code != .cancelled {
                Logger.spotify.error("Artwork download failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private func insert(_ image: NSImage, for url: URL) {
        cache[url] = image
        markRecentlyUsed(url)
        while recentURLs.count > capacity {
            cache[recentURLs.removeFirst()] = nil
        }
    }

    private func markRecentlyUsed(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.append(url)
    }
}
