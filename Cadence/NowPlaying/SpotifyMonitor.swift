import AppKit
import os

extension Notification.Name {
    static let spotifyPlaybackStateChanged = Notification.Name("com.spotify.client.PlaybackStateChanged")
}

/// Watches for Spotify events and passes them to `SpotifyService`.
@MainActor
final class SpotifyMonitor: NSObject {
    private nonisolated let service: SpotifyService
    private var workspaceObservers: [NSObjectProtocol] = []
    private var loggedUserInfoKeys = false

    init(service: SpotifyService) {
        self.service = service
        super.init()
    }

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let service = self.service

        // AppKit holds distributed notifications while the app isn't active, and a
        // menu-bar app almost never is. Spotify's must arrive right away.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playbackStateChanged(_:)),
            name: .spotifyPlaybackStateChanged,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard Self.isSpotify(notification) else { return }
            Task { await service.spotifyLaunched() }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard Self.isSpotify(notification) else { return }
            Task { await service.spotifyTerminated() }
        })

        Task { await service.refresh() }
    }

    @objc private nonisolated func playbackStateChanged(_ notification: Notification) {
        let playerState = notification.userInfo?["Player State"] as? String
        let keys = notification.userInfo.map { $0.keys.map { String(describing: $0.base) }.sorted() } ?? []
        Task { @MainActor in self.logUserInfoKeysOnce(keys) }
        Task { await service.playbackStateChanged(playerState: playerState) }
    }

    private nonisolated static func isSpotify(_ notification: Notification) -> Bool {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == SpotifyService.bundleIdentifier
    }

    private func logUserInfoKeysOnce(_ keys: [String]) {
        guard !loggedUserInfoKeys else { return }
        loggedUserInfoKeys = true
        Logger.spotify.notice("PlaybackStateChanged userInfo keys: \(keys.joined(separator: ", "), privacy: .public)")
    }
}
