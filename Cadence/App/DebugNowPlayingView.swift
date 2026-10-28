#if DEBUG
import SwiftUI

/// Temporary window for checking Brief 01 before the real UI exists. Debug builds only.
struct DebugNowPlayingView: View {
    static let windowID = "debug-now-playing"

    let store: NowPlayingStore
    let spotify: SpotifyService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.automationDenied {
                automationDeniedBanner
            }
            HStack(alignment: .top, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.track?.title ?? "Nothing playing")
                        .font(.headline)
                    Text(store.track?.artist ?? "—")
                    Text(store.track?.album ?? "—")
                        .foregroundStyle(.secondary)
                    Text("State: \(String(describing: store.state))")
                        .font(.caption.monospaced())
                    Text(store.track?.id ?? "")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            progress
            controls
        }
        .padding()
        .frame(width: 400)
    }

    private var artwork: some View {
        Group {
            if let image = store.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(.rect(cornerRadius: 8))
    }

    private var progress: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: store.state != .playing)) { context in
            let duration = store.track?.durationSeconds ?? 0
            let position = store.currentPosition(at: context.date)
            VStack(spacing: 4) {
                ProgressView(value: min(position, max(duration, 1)), total: max(duration, 1))
                HStack {
                    Text(Formatting.playbackTime(position))
                    Spacer()
                    Text(Formatting.playbackTime(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                Button("Previous", systemImage: "backward.fill") {
                    Task { await spotify.previous() }
                }
                Button("Back 15 seconds", systemImage: "gobackward.15") {
                    seek(by: -15)
                }
                Button(
                    store.state == .playing ? "Pause" : "Play",
                    systemImage: store.state == .playing ? "pause.fill" : "play.fill"
                ) {
                    Task { await spotify.playPause() }
                }
                Button("Forward 15 seconds", systemImage: "goforward.15") {
                    seek(by: 15)
                }
                Button("Next", systemImage: "forward.fill") {
                    Task { await spotify.next() }
                }
            }
            .disabled(store.track == nil)

            Spacer()

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await spotify.refresh() }
            }
        }
        .labelStyle(.iconOnly)
    }

    private var automationDeniedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Allow Cadence to control Spotify")
                .font(.headline)
            Text("Turn on Spotify under Cadence in System Settings → Privacy & Security → Automation, then press Refresh.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Automation Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.15), in: .rect(cornerRadius: 8))
    }

    private func seek(by delta: Double) {
        let target = store.currentPosition() + delta
        Task { await spotify.seek(to: target) }
    }
}
#endif
