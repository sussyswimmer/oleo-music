import SwiftUI

/// The lock screen player: a glass card like iPhone's Now Playing widget.
/// Display-only when clicks can't reach the lock screen: no controls, nothing that looks tappable.
struct LockScreenView: View {
    let store: NowPlayingStore
    let spotify: SpotifyService
    let interactive: Bool
    /// Tapping the artwork opens full-screen art (Brief 05).
    let onArtworkTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ArtworkImage(image: store.artwork, cornerRadius: 10)
                    .frame(width: 64, height: 64)
                    .onTapGesture {
                        if interactive {
                            onArtworkTap()
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.track?.title ?? "")
                        .font(.headline)
                    Text(store.track?.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .id(store.track?.id)
                .transition(.push(from: .bottom))
                Spacer(minLength: 0)
            }
            .clipped()
            .animation(.spring(duration: 0.4), value: store.track?.id)

            progress

            if interactive {
                controls
            }
        }
        .padding(18)
        .frame(width: 360)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .environment(\.colorScheme, .dark)
    }

    private var progress: some View {
        // Once a second is plenty on the lock screen; paused unless playing.
        TimelineView(.animation(minimumInterval: 1, paused: store.state != .playing)) { context in
            let duration = store.track?.durationSeconds ?? 0
            let position = store.currentPosition(at: context.date)
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.25))
                        Capsule()
                            .fill(.white)
                            .frame(width: geometry.size.width * (duration > 0 ? min(position / duration, 1) : 0))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Formatting.playbackTime(position))
                    Spacer()
                    Text("-" + Formatting.playbackTime(duration - position))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
            controlButton(.previous, systemImage: "backward.fill")
            controlButton(.playPause, systemImage: store.state == .playing ? "pause.fill" : "play.fill")
            controlButton(.next, systemImage: "forward.fill")
        }
        .font(.title2)
        .frame(maxWidth: .infinity)
    }

    private enum Control {
        case previous, playPause, next
    }

    private func controlButton(_ control: Control, systemImage: String) -> some View {
        Button {
            let spotify = self.spotify
            Task {
                switch control {
                case .previous: await spotify.previous()
                case .playPause: await spotify.playPause()
                case .next: await spotify.next()
                }
            }
        } label: {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
