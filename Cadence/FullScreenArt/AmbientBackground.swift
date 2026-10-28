import SwiftUI

extension PaletteColor {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

/// A slowly drifting mesh gradient in the artwork's colors, darkened a little so
/// white text stays readable. Cross-fades when the palette changes.
struct AmbientBackground: View {
    enum Motion {
        /// Playing: smooth drift.
        case flowing
        /// Paused: the same drift, redrawn rarely.
        case slow
        /// Nothing loaded: no animation at all.
        case still
    }

    let palette: [PaletteColor]
    let motion: Motion

    var body: some View {
        ZStack {
            DriftingMesh(colors: Self.meshColors(from: palette), motion: motion)
                .id(palette)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 1), value: palette)
        .overlay(.black.opacity(0.28))
    }

    /// Nine colors for a 3 × 3 mesh, with darker corners so the middle glows.
    static func meshColors(from palette: [PaletteColor]) -> [PaletteColor] {
        let colors = palette.isEmpty ? PaletteExtractor.fallback : palette
        let order = [1, 2, 3, 3, 0, 4, 2, 1, 0]
        let corners: Set = [0, 2, 6, 8]
        return order.enumerated().map { slot, index in
            let color = colors[index % colors.count]
            return corners.contains(slot) ? color.scaled(brightness: 0.6) : color
        }
    }
}

private struct DriftingMesh: View {
    let colors: [PaletteColor]
    let motion: AmbientBackground.Motion

    /// Rendered at this fraction of full size, then scaled up: the gradient is
    /// smooth anyway, and it keeps the GPU cost of a full-screen animation low.
    private static let renderScale: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: motion == .slow ? 0.5 : 1.0 / 20, paused: motion == .still)) { context in
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: Self.points(at: context.date.timeIntervalSinceReferenceDate),
                    colors: colors.map(\.color)
                )
                .frame(width: geometry.size.width / Self.renderScale, height: geometry.size.height / Self.renderScale)
                .blur(radius: 6, opaque: true)
                .drawingGroup()
                .scaleEffect(Self.renderScale, anchor: .topLeading)
            }
        }
        .clipped()
    }

    /// The 3 × 3 control points: corners fixed, the rest drifting on slow,
    /// unrelated cycles so the pattern doesn't visibly repeat.
    private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func drift(period: Double, phase: Double) -> Float {
            Float(sin(time * 2 * .pi / period + phase)) * 0.12
        }
        let top: Float = 0.5 + drift(period: 23, phase: 0)
        let left: Float = 0.5 + drift(period: 29, phase: 1)
        let centerX: Float = 0.5 + drift(period: 19, phase: 2)
        let centerY: Float = 0.5 + drift(period: 31, phase: 3)
        let right: Float = 0.5 + drift(period: 27, phase: 4)
        let bottom: Float = 0.5 + drift(period: 25, phase: 5)
        return [
            SIMD2(0, 0), SIMD2(top, 0), SIMD2(1, 0),
            SIMD2(0, left), SIMD2(centerX, centerY), SIMD2(1, right),
            SIMD2(0, 1), SIMD2(bottom, 1), SIMD2(1, 1),
        ]
    }
}
