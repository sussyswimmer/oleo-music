import SwiftUI

/// What the spike card shows about input reaching it.
@Observable
@MainActor
final class LockScreenSpikeModel {
    private(set) var inputCount = 0
    private(set) var hoverCount = 0
    private(set) var lastEvent = "none"
    private(set) var level: Int32 = 0

    func reset(level: Int32) {
        inputCount = 0
        hoverCount = 0
        lastEvent = "none"
        self.level = level
    }

    func recordEvent(_ name: String) {
        inputCount += 1
        lastEvent = name
    }

    func recordHover() {
        hoverCount += 1
    }
}

/// Brief 02's throwaway lock screen card: now playing, controls, a live clock to
/// show it keeps rendering, and counters showing whether input arrives.
struct LockScreenSpikeView: View {
    let store: NowPlayingStore
    let spotify: SpotifyService
    let model: LockScreenSpikeModel
    let onAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.track?.title ?? "Nothing playing")
                        .font(.headline)
                    Text(store.track?.artist ?? "—")
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: 24) {
                control(.previous, systemImage: "backward.fill")
                control(.playPause, systemImage: store.state == .playing ? "pause.fill" : "play.fill")
                control(.next, systemImage: "forward.fill")
            }
            .font(.title2)
            .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
            }
            Text("Input events: \(model.inputCount)   Hovers: \(model.hoverCount)   Level: \(model.level)")
                .font(.caption.monospacedDigit())
            Text("Last event: \(model.lastEvent)")
                .font(.caption.monospaced())
                .foregroundStyle(.red)
        }
        .padding(16)
        .frame(width: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .onHover { inside in
            if inside {
                model.recordHover()
                onAction("hover")
            }
        }
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
        .frame(width: 56, height: 56)
        .clipShape(.rect(cornerRadius: 8))
    }

    private enum Action: String {
        case previous, playPause = "play/pause", next
    }

    private func control(_ action: Action, systemImage: String) -> some View {
        Button {
            onAction(action.rawValue)
            let spotify = self.spotify
            Task {
                switch action {
                case .previous: await spotify.previous()
                case .playPause: await spotify.playPause()
                case .next: await spotify.next()
                }
            }
        } label: {
            Image(systemName: systemImage)
        }
        .buttonStyle(.plain)
    }
}
