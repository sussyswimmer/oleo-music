import SwiftUI

/// Layout and expansion state shared by `NotchPanelController` and `NotchView`.
/// Rects are in the view's coordinates: origin at the top left of the canvas.
@Observable
@MainActor
final class NotchPanelState {
    var isExpanded = false
    private(set) var canvasSize: CGSize = .zero
    private(set) var collapsedRect: CGRect = .zero
    private(set) var chipRect: CGRect = .zero
    private(set) var expandedRect: CGRect = .zero
    private(set) var bandHeight: CGFloat = 0

    func update(geometry: NotchGeometry, frames: NotchGeometry.Frames) {
        let canvas = frames.canvas
        canvasSize = canvas.size
        collapsedRect = NotchGeometry.local(frames.collapsed, in: canvas)
        chipRect = NotchGeometry.local(frames.chip, in: canvas)
        expandedRect = NotchGeometry.local(frames.expandedPanel, in: canvas)
        bandHeight = geometry.bandHeight
    }
}

/// One black shape that is the art chip plus notch when collapsed and grows into
/// the player when expanded. Black, so it merges with the hardware notch.
struct NotchView: View {
    let store: NowPlayingStore
    let spotify: SpotifyService
    let state: NotchPanelState
    var layout = NotchLayout.standard

    var body: some View {
        let shape = state.isExpanded ? state.expandedRect : state.collapsedRect
        let radius = state.isExpanded ? layout.expandedCornerRadius : layout.collapsedCornerRadius

        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .fill(.black)
                .shadow(color: .black.opacity(state.isExpanded ? 0.35 : 0), radius: 12, y: 6)
                .frame(width: shape.width, height: shape.height)
                .offset(x: shape.minX, y: shape.minY)

            if state.isExpanded {
                NotchPlayerView(store: store, spotify: spotify)
                    .padding(.top, state.bandHeight)
                    .frame(width: state.expandedRect.width, height: state.expandedRect.height, alignment: .top)
                    .offset(x: state.expandedRect.minX, y: state.expandedRect.minY)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeIn(duration: 0.2).delay(0.1)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
            } else {
                ArtworkChip(store: store)
                    .frame(width: state.chipRect.width, height: state.chipRect.height)
                    .offset(x: state.chipRect.minX, y: state.chipRect.minY)
                    .transition(.opacity)
            }
        }
        .frame(width: state.canvasSize.width, height: state.canvasSize.height, alignment: .topLeading)
        // The window sits in the notch area; positions are absolute, so no safe-area insets.
        .ignoresSafeArea()
    }
}

/// The small artwork beside the notch. Dims a moment after playback pauses.
private struct ArtworkChip: View {
    let store: NowPlayingStore

    var body: some View {
        let paused = store.state == .paused
        ArtworkImage(image: store.artwork, cornerRadius: 5)
            .opacity(paused ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.4).delay(paused ? 2 : 0), value: paused)
    }
}

/// Album art that cross-fades when the image changes.
private struct ArtworkImage: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.white.opacity(0.12))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: image.map { ObjectIdentifier($0) })
    }
}

/// The expanded player: artwork, title, artist, scrubbable progress, controls.
private struct NotchPlayerView: View {
    let store: NowPlayingStore
    let spotify: SpotifyService
    /// While dragging the progress bar, and until the seek lands.
    @State private var scrubFraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ArtworkImage(image: store.artwork, cornerRadius: 10)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.track?.title ?? "")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(store.track?.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .lineLimit(1)
                .id(store.track?.id)
                .transition(.push(from: .bottom))
                Spacer(minLength: 0)
            }
            .clipped()
            .animation(.spring(duration: 0.4), value: store.track?.id)

            progress
            controls
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var progress: some View {
        // Exists only while expanded, and pauses unless playing: no cost when collapsed.
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: store.state != .playing || scrubFraction != nil)) { context in
            let duration = store.track?.durationSeconds ?? 0
            let position = scrubFraction.map { $0 * duration } ?? store.currentPosition(at: context.date)
            VStack(spacing: 4) {
                ScrubBar(fraction: duration > 0 ? min(max(position / duration, 0), 1) : 0) { fraction in
                    scrubFraction = fraction
                } onCommit: { fraction in
                    seek(to: fraction, of: duration)
                }
                HStack {
                    Text(Formatting.playbackTime(position))
                    Spacer()
                    Text("-" + Formatting.playbackTime(duration - position))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            controlButton(.previous, systemImage: "backward.fill")
            controlButton(.playPause, systemImage: store.state == .playing ? "pause.fill" : "play.fill")
            controlButton(.next, systemImage: "forward.fill")
        }
        .font(.title3)
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
                .frame(width: 36, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func seek(to fraction: Double, of duration: Double) {
        scrubFraction = fraction
        let spotify = self.spotify
        Task {
            await spotify.seek(to: fraction * duration)
            // The seek refreshes the store, so the bar can follow it again.
            scrubFraction = nil
        }
    }
}

/// A thin progress bar you can drag along. Reports fractions from 0 to 1.
private struct ScrubBar: View {
    let fraction: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white)
                    .frame(width: width * fraction)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onChange(Self.fraction(at: $0.location.x, width: width)) }
                    .onEnded { onCommit(Self.fraction(at: $0.location.x, width: width)) }
            )
        }
        .frame(height: 14)
    }

    private nonisolated static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        width > 0 ? min(max(Double(x / width), 0), 1) : 0
    }
}
