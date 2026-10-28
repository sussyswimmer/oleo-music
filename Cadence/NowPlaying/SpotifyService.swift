import AppKit
import os

/// What Spotify reported in one refresh.
struct SpotifySnapshot: Equatable, Sendable {
    var state: PlaybackState
    var positionSeconds: Double
    var track: Track?
    /// When the values were read. The store ignores snapshots older than one it already has.
    var readAt: Date

    static func idle(at date: Date = .now) -> SpotifySnapshot {
        SpotifySnapshot(state: .idle, positionSeconds: 0, track: nil, readAt: date)
    }
}

extension SpotifySnapshot {
    /// Builds a snapshot from the values the refresh script returns.
    /// Spotify reports duration in milliseconds and position in seconds.
    init(
        playerState: String,
        positionSeconds: Double,
        trackID: String,
        title: String,
        artist: String,
        album: String,
        durationMilliseconds: Double,
        artworkURL: String,
        readAt: Date
    ) {
        let state: PlaybackState = switch playerState {
        case "playing": .playing
        case "paused": .paused
        default: .idle
        }
        self.state = state
        self.positionSeconds = positionSeconds.isFinite ? max(0, positionSeconds) : 0
        self.readAt = readAt
        if state == .idle || trackID.isEmpty {
            track = nil
        } else {
            track = Track(
                id: trackID,
                title: title,
                artist: artist,
                album: album,
                durationSeconds: durationMilliseconds.isFinite ? max(0, durationMilliseconds / 1000) : 0,
                artworkURL: URL(string: artworkURL)
            )
        }
    }
}

enum SpotifyScriptError: Error, Equatable {
    /// The user denied Cadence's Automation permission for Spotify.
    case notPermitted
    /// Spotify quit while we were talking to it.
    case notRunning
    /// Anything else, including -609 (connection invalid), which a compiled script
    /// can hit after Spotify relaunches. Worth retrying.
    case failed(code: Int, message: String)

    init(code: Int, message: String) {
        switch code {
        case -1743, -1744: self = .notPermitted // errAEEventNotPermitted, errAEEventWouldRequireUserConsent
        case -600: self = .notRunning // procNotFound
        default: self = .failed(code: code, message: message)
        }
    }

    init(errorInfo: NSDictionary?) {
        self.init(
            code: errorInfo?[NSAppleScript.errorNumber] as? Int ?? 0,
            message: errorInfo?[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        )
    }
}

/// Reads and controls the Spotify desktop app over AppleScript.
///
/// Every script runs on this actor's own serial queue, never on the main thread,
/// and every script checks that Spotify is running first: a `tell application`
/// to an app that isn't running launches it.
actor SpotifyService {
    static let bundleIdentifier = "com.spotify.client"
    static let pollInterval = Duration.seconds(5)

    /// Whether Spotify is running, without sending it anything.
    static var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { !$0.isTerminated }
    }

    private let store: NowPlayingStore
    // AppleScript blocks its thread until Spotify replies, so it gets its own
    // queue instead of a thread from Swift's shared pool. Draining the autorelease
    // pool per job keeps AppleScript's Objective-C results from piling up.
    private let queue = DispatchSerialQueue(label: "com.maxwell.cadence.spotify", autoreleaseFrequency: .workItem)
    private var compiledScripts: [String: NSAppleScript] = [:]
    private var lastState = PlaybackState.idle
    private var lastRefreshFailed = false
    private var automationDenied = false
    private var pollTask: Task<Void, Never>?

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    init(store: NowPlayingStore) {
        self.store = store
    }

    // MARK: Events

    /// Reads Spotify's state and publishes it to the store.
    func refresh() async {
        guard Self.isRunning else {
            await publish(.idle())
            return
        }
        do throws(SpotifyScriptError) {
            let snapshot = try readSnapshot()
            await setAutomationDenied(false)
            await publish(snapshot)
        } catch {
            await handle(error)
        }
    }

    /// Spotify posted `com.spotify.client.PlaybackStateChanged`.
    func playbackStateChanged(playerState: String?) async {
        // Spotify posts "Stopped" as it quits. Don't script it then: if it exits
        // between the "is running" check and the first Apple Event, AppleScript
        // would launch it again.
        if playerState == "Stopped" {
            await publish(.idle())
        } else {
            await refresh()
        }
    }

    func spotifyLaunched() async {
        // Compiled scripts can hold a connection to the previous Spotify process.
        compiledScripts.removeAll()
        // Give Spotify a moment to start answering Apple Events.
        try? await Task.sleep(for: .seconds(1.5))
        await refresh()
    }

    func spotifyTerminated() async {
        compiledScripts.removeAll()
        await publish(.idle())
    }

    // MARK: Controls

    func playPause() async {
        await perform("playpause")
    }

    func next() async {
        await perform("next track")
    }

    func previous() async {
        await perform("previous track")
    }

    func seek(to seconds: Double) async {
        // String(format:) without a locale always uses "." for decimals, which AppleScript source needs.
        let position = String(format: "%.3f", max(0, seconds))
        await perform("set player position to \(position)", cacheScript: false)
    }

    private func perform(_ command: String, cacheScript: Bool = true) async {
        guard Self.isRunning else { return }
        do throws(SpotifyScriptError) {
            _ = try run(Self.commandScript(command), cache: cacheScript)
        } catch {
            await handle(error)
            return
        }
        await refresh()
    }

    // MARK: State

    private func publish(_ snapshot: SpotifySnapshot) async {
        lastState = snapshot.state
        lastRefreshFailed = false
        updatePolling()
        await store.apply(snapshot)
    }

    private func handle(_ error: SpotifyScriptError) async {
        switch error {
        case .notPermitted:
            Logger.spotify.error("Not allowed to control Spotify (Automation permission)")
            // Don't poll: a denied request fails the same way until the user changes the setting.
            lastRefreshFailed = false
            updatePolling()
            await setAutomationDenied(true)
        case .notRunning:
            await publish(.idle())
        case .failed(let code, let message):
            Logger.spotify.error("Spotify script failed (\(code)): \(message, privacy: .public)")
            // Recompile on the next try in case the failure was a stale connection.
            compiledScripts.removeAll()
            lastRefreshFailed = true
            updatePolling()
        }
    }

    private func setAutomationDenied(_ denied: Bool) async {
        guard denied != automationDenied else { return }
        automationDenied = denied
        await store.setAutomationDenied(denied)
    }

    /// The safety poll catches anything the notifications missed. It runs only
    /// while playing, or to retry after a failed refresh.
    private func updatePolling() {
        guard lastState == .playing || lastRefreshFailed else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval, tolerance: .seconds(1))
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    // MARK: AppleScript

    private func readSnapshot() throws(SpotifyScriptError) -> SpotifySnapshot {
        let readAt = Date.now
        let result = try run(Self.refreshScript, cache: true)
        // The script returns {"notRunning"} if Spotify quit just before it ran.
        guard result.numberOfItems >= 8 else { return .idle(at: readAt) }

        func text(_ index: Int) -> String { result.atIndex(index)?.stringValue ?? "" }
        func number(_ index: Int) -> Double { result.atIndex(index)?.doubleValue ?? 0 }

        return SpotifySnapshot(
            playerState: text(1),
            positionSeconds: number(2),
            trackID: text(3),
            title: text(4),
            artist: text(5),
            album: text(6),
            durationMilliseconds: number(7),
            artworkURL: text(8),
            readAt: readAt
        )
    }

    private func run(_ source: String, cache: Bool) throws(SpotifyScriptError) -> NSAppleEventDescriptor {
        let script: NSAppleScript
        if let cached = compiledScripts[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else {
                throw .failed(code: 0, message: "Couldn't create the script")
            }
            var compileError: NSDictionary?
            guard compiled.compileAndReturnError(&compileError) else {
                throw SpotifyScriptError(errorInfo: compileError)
            }
            if cache {
                compiledScripts[source] = compiled
            }
            script = compiled
        }
        var executeError: NSDictionary?
        let result = script.executeAndReturnError(&executeError)
        if let executeError {
            throw SpotifyScriptError(errorInfo: executeError)
        }
        return result
    }

    /// One call for everything: returns a list, so titles with any characters come back
    /// intact and numbers keep their type (text conversion would use the locale's decimal comma).
    private static let refreshScript = """
        if application id "com.spotify.client" is not running then return {"notRunning"}
        with timeout of 10 seconds
            tell application id "com.spotify.client"
                set playerState to player state as text
                set playerPosition to player position
                set trackValues to {"", "", "", "", 0, ""}
                try
                    set t to current track
                    set trackValues to {id of t, name of t, artist of t, album of t, duration of t, artwork url of t}
                end try
            end tell
        end timeout
        set cleanValues to {}
        repeat with itemRef in trackValues
            set itemValue to contents of itemRef
            if itemValue is missing value then set itemValue to ""
            set end of cleanValues to itemValue
        end repeat
        return {playerState, playerPosition} & cleanValues
        """

    private static func commandScript(_ command: String) -> String {
        """
        if application id "com.spotify.client" is not running then return
        with timeout of 5 seconds
            tell application id "com.spotify.client" to \(command)
        end timeout
        """
    }
}
