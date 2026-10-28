import Foundation
import Testing
@testable import Cadence

/// A 32 × 32 RGBA image filled by `color(x, y)`, which returns (r, g, b, a).
private func image(_ color: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> [UInt8] {
    var pixels: [UInt8] = []
    for y in 0..<32 {
        for x in 0..<32 {
            let (r, g, b, a) = color(x, y)
            pixels += [r, g, b, a]
        }
    }
    return pixels
}

private let red = PaletteColor(red: 1, green: 0, blue: 0)
private let blue = PaletteColor(red: 0, green: 0, blue: 1)
private let yellow = PaletteColor(red: 1, green: 1, blue: 0)

/// Hue distance around the color wheel, 0 to 0.5.
private func hueDistance(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b)
    return min(d, 1 - d)
}

struct PaletteExtractorTests {
    @Test func solidColorFillsOutToThreeShadesOfIt() throws {
        let palette = PaletteExtractor.palette(fromRGBA: image { _, _ in (255, 0, 0, 255) })
        #expect(palette.count == 3)
        let first = try #require(palette.first)
        #expect(first.distance(to: red) < 0.01)
        #expect(palette.allSatisfy { hueDistance($0.hue, 0) < 0.1 })
    }

    @Test func dominantColorComesFirst() {
        // 60% blue, 40% yellow.
        let palette = PaletteExtractor.palette(fromRGBA: image { x, _ in x < 19 ? (0, 0, 255, 255) : (255, 255, 0, 255) })
        #expect(palette.count >= 3)
        #expect(palette[0].distance(to: blue) < 0.01)
        #expect(palette[1].distance(to: yellow) < 0.01)
    }

    @Test(arguments: [
        ("black and white", image { x, y in (x + y).isMultiple(of: 2) ? (0, 0, 0, 255) : (255, 255, 255, 255) }),
        ("grey", image { _, _ in (128, 128, 128, 255) }),
        ("near black red", image { _, _ in (40, 0, 0, 255) }),
        ("dull beige", image { _, _ in (200, 190, 170, 255) }),
        ("transparent", image { _, _ in (255, 0, 0, 0) }),
    ])
    func coversWithoutVividColorsGetTheFallback(name: String, pixels: [UInt8]) {
        #expect(PaletteExtractor.palette(fromRGBA: pixels) == PaletteExtractor.fallback, "\(name)")
    }

    @Test func vividColorOnABlackCoverIsKept() throws {
        // Mostly black with an orange band: the black is skipped, the orange wins.
        let palette = PaletteExtractor.palette(fromRGBA: image { _, y in y < 6 ? (255, 128, 0, 255) : (5, 5, 5, 255) })
        let first = try #require(palette.first)
        #expect(first.distance(to: PaletteColor(red: 1, green: 0.5, blue: 0)) < 0.01)
    }

    @Test func specksBelowOnePercentAreIgnored() {
        // 5 green pixels out of 1024.
        let palette = PaletteExtractor.palette(fromRGBA: image { x, y in y == 0 && x < 5 ? (0, 255, 0, 255) : (255, 0, 0, 255) })
        #expect(palette.allSatisfy { hueDistance($0.hue, 1.0 / 3) > 0.2 })
    }

    @Test func transparentPixelsAreIgnored() {
        let palette = PaletteExtractor.palette(fromRGBA: image { x, _ in x < 16 ? (0, 255, 0, 0) : (255, 0, 0, 255) })
        #expect(palette.allSatisfy { hueDistance($0.hue, 0) < 0.1 })
    }

    @Test func atMostFiveDistinctColors() {
        // Eight vivid hues in equal stripes.
        let palette = PaletteExtractor.palette(fromRGBA: image { x, _ in
            let c = PaletteColor(hue: Double(x / 4) / 8, saturation: 1, brightness: 1)
            return (UInt8(c.red * 255), UInt8(c.green * 255), UInt8(c.blue * 255), 255)
        })
        #expect(palette.count == 5)
        for (i, a) in palette.enumerated() {
            for b in palette[(i + 1)...] {
                #expect(a.distance(to: b) >= PaletteExtractor.minimumDistance)
            }
        }
    }

    @Test func sameInputSameOutput() {
        let pixels = image { x, y in (UInt8(x * 8), UInt8(y * 8), UInt8((x + y) * 4), 255) }
        #expect(PaletteExtractor.palette(fromRGBA: pixels) == PaletteExtractor.palette(fromRGBA: pixels))
    }

    @Test func hueSaturationBrightnessRoundTrip() {
        for color in [red, blue, yellow, PaletteColor(red: 0.2, green: 0.6, blue: 0.4), PaletteColor(red: 0.9, green: 0.3, blue: 0.7)] {
            let back = PaletteColor(hue: color.hue, saturation: color.saturation, brightness: color.brightness)
            #expect(back.distance(to: color) < 1e-9)
        }
    }

    #if canImport(AppKit)
    @Test func readsColorsFromAnNSImage() throws {
        let nsImage = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            NSRect(x: 0, y: 0, width: 64, height: 40).fill()
            NSColor.systemYellow.setFill()
            NSRect(x: 0, y: 40, width: 64, height: 24).fill()
            return true
        }
        let palette = PaletteExtractor.palette(from: nsImage)
        let first = try #require(palette.first)
        #expect(hueDistance(first.hue, 0.6) < 0.08, "blue covers most of the image")
        #expect(palette.contains { hueDistance($0.hue, 0.14) < 0.06 }, "yellow is in the palette")
    }
    #endif
}
