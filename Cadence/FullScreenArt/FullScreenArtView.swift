import SwiftUI

/// Full-screen album art over the lock screen: the clock above a huge cover,
/// title and artist below, all on a background drawn from the cover's colors.
struct FullScreenArtView: View {
    let store: NowPlayingStore
    /// Shared with the lock screen card so the artwork grows out of it.
    let artworkNamespace: Namespace.ID
    let size: CGSize

    var body: some View {
        let coverSize = size.height * 0.5
        ZStack {
            AmbientBackground(palette: store.palette, motion: motion)
            VStack(spacing: size.height * 0.035) {
                BigClockView(fontSize: size.height * 0.1)
                ArtworkImage(image: store.artwork, cornerRadius: coverSize * 0.04)
                    .matchedGeometryEffect(id: LockScreenView.artworkID, in: artworkNamespace)
                    .frame(width: coverSize, height: coverSize)
                    .shadow(color: .black.opacity(0.45), radius: 40, y: 20)
                VStack(spacing: 4) {
                    Text(store.track?.title ?? "")
                        .font(.title2.weight(.semibold))
                    Text(store.track?.artist ?? "")
                        .font(.title3)
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: coverSize)
                .shadow(color: .black.opacity(0.3), radius: 6)
                progress(width: coverSize)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var motion: AmbientBackground.Motion {
        switch store.state {
        case .playing: .flowing
        case .paused: .slow
        case .idle: .still
        }
    }

    private func progress(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1, paused: store.state != .playing)) { context in
            let duration = store.track?.durationSeconds ?? 0
            let position = store.currentPosition(at: context.date)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.25))
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: width * (duration > 0 ? min(position / duration, 1) : 0))
            }
            .frame(width: width, height: 3)
        }
    }
}
