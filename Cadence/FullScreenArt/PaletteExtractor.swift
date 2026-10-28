import AppKit

/// An sRGB color with components from 0 to 1.
struct PaletteColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From hue, saturation and brightness, each 0 to 1. Hue wraps around.
    init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = brightness - chroma
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    var brightness: Double { max(red, green, blue) }

    var saturation: Double {
        brightness == 0 ? 0 : (brightness - min(red, green, blue)) / brightness
    }

    var hue: Double {
        let delta = brightness - min(red, green, blue)
        guard delta > 0 else { return 0 }
        let sector = switch brightness {
        case red: (green - blue) / delta
        case green: 2 + (blue - red) / delta
        default: 4 + (red - green) / delta
        }
        let hue = sector / 6
        return hue < 0 ? hue + 1 : hue
    }

    func distance(to other: PaletteColor) -> Double {
        let r = red - other.red, g = green - other.green, b = blue - other.blue
        return (r * r + g * g + b * b).squareRoot()
    }

    /// The same hue and saturation at `factor` times the brightness.
    func scaled(brightness factor: Double) -> PaletteColor {
        PaletteColor(hue: hue, saturation: saturation, brightness: min(1, brightness * factor))
    }
}

/// Picks the colors for the ambient background from album artwork.
enum PaletteExtractor {
    /// Artwork is downsampled to this many pixels square before sampling.
    static let sampleSize = 32
    static let maximumColors = 5
    static let minimumColors = 3
    /// Colors covering less than this share of the opaque pixels are noise.
    static let minimumShare = 0.01
    /// Colors closer than this (RGB distance, 0 to √3) count as the same color.
    static let minimumDistance = 0.22

    /// For covers with no vivid colors: black and white, grayscale, very dark.
    static let fallback = [
        PaletteColor(red: 0.20, green: 0.24, blue: 0.48),
        PaletteColor(red: 0.42, green: 0.22, blue: 0.50),
        PaletteColor(red: 0.12, green: 0.38, blue: 0.45),
    ]

    /// Near-black, near-white, grey and dull colors make a muddy background.
    static func isVibrant(_ color: PaletteColor) -> Bool {
        color.brightness >= 0.2 && color.saturation >= 0.25
    }

    /// The palette of an image given as RGBA pixels, 8 bits per channel. Returns 3 to
    /// 5 distinct colors, the most dominant first, weighted towards vivid ones.
    static func palette(fromRGBA pixels: [UInt8]) -> [PaletteColor] {
        var buckets: [Int: (count: Int, red: Double, green: Double, blue: Double)] = [:]
        var opaquePixels = 0
        for index in stride(from: 0, to: pixels.count - 3, by: 4) where pixels[index + 3] >= 128 {
            opaquePixels += 1
            let color = PaletteColor(
                red: Double(pixels[index]) / 255,
                green: Double(pixels[index + 1]) / 255,
                blue: Double(pixels[index + 2]) / 255
            )
            guard isVibrant(color) else { continue }
            let key = bucketKey(for: color)
            var bucket = buckets[key, default: (0, 0, 0, 0)]
            bucket.count += 1
            bucket.red += color.red
            bucket.green += color.green
            bucket.blue += color.blue
            buckets[key] = bucket
        }

        let minimumCount = max(1, Int((Double(opaquePixels) * minimumShare).rounded(.up)))
        var ranked: [Candidate] = []
        for (key, bucket) in buckets where bucket.count >= minimumCount {
            let count = Double(bucket.count)
            let average = PaletteColor(red: bucket.red / count, green: bucket.green / count, blue: bucket.blue / count)
            let score = count * (0.5 + average.saturation * average.brightness)
            ranked.append(Candidate(key: key, color: average, score: score))
        }
        // The key breaks ties so the result never depends on dictionary order.
        ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.key < $1.key }

        var chosen: [PaletteColor] = []
        for candidate in ranked where chosen.count < maximumColors {
            if chosen.allSatisfy({ $0.distance(to: candidate.color) >= minimumDistance }) {
                chosen.append(candidate.color)
            }
        }
        guard !chosen.isEmpty else { return fallback }

        // One or two colors: add darker and slightly shifted shades of them.
        var index = 0
        while chosen.count < minimumColors {
            let base = chosen[index % chosen.count]
            chosen.append(index.isMultiple(of: 2)
                ? base.scaled(brightness: 0.55)
                : PaletteColor(hue: base.hue + 0.06, saturation: base.saturation, brightness: base.brightness * 0.8))
            index += 1
        }
        return chosen
    }

    private struct Candidate {
        let key: Int
        let color: PaletteColor
        let score: Double
    }

    /// Groups similar colors: 24 hues, 4 saturations, 4 brightnesses.
    private static func bucketKey(for color: PaletteColor) -> Int {
        let hue = min(Int(color.hue * 24), 23)
        let saturation = min(Int(color.saturation * 4), 3)
        let brightness = min(Int(color.brightness * 4), 3)
        return hue * 16 + saturation * 4 + brightness
    }
}

// MARK: NSImage

extension PaletteExtractor {
    static func palette(from image: NSImage) -> [PaletteColor] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return fallback
        }
        let size = sampleSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return drawn ? palette(fromRGBA: pixels) : fallback
    }
}
