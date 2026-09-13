import AppKit
import SwiftUI

/// Colours sampled from album artwork.
///
/// Used for the scrubber tint when Settings > Appearance is set to "Album Artwork", and it
/// is what the V2 visualiser will key its bars to. Sampling is done on a tiny downscaled
/// bitmap, which is fast enough to run on every track change without a cache.
struct ArtworkPalette: Equatable {
    var primary: Color
    var secondary: Color
    /// True when the artwork is light overall, so overlaid text should be dark.
    var isLight: Bool

    /// The artwork colours lifted for use as light.
    ///
    /// A muted or dark cover yields a muted, dark glow, which reads as the effect being
    /// broken rather than as faithful colour. Hue is kept exactly; saturation and brightness
    /// get a floor, so every album produces light that is actually visible. Rainbow mode
    /// looked like the only working style purely because it builds its colours at full
    /// saturation and never went through the artwork.
    var glowPrimary: Color { Self.lifted(primary) }
    var glowSecondary: Color { Self.lifted(secondary) }

    private static func lifted(_ color: Color) -> Color {
        guard let source = NSColor(color).usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(
            hue: Double(hue),
            saturation: Double(max(saturation, 0.72)),
            brightness: Double(max(brightness, 0.92))
        )
    }

    static let fallback = ArtworkPalette(
        primary: Palette.controlAccent,
        secondary: Palette.secondaryText,
        isLight: false
    )

    /// Samples `image` by drawing it into an 8x8 bitmap and picking the most colourful
    /// pixel as the primary, with the average as the secondary.
    static func extract(from image: NSImage) -> ArtworkPalette {
        let side = 8
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4,
            bitsPerPixel: 32
        ) else { return .fallback }

        let context = NSGraphicsContext(bitmapImageRep: representation)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var bestScore = -1.0
        var best = NSColor.systemBlue
        var totalRed = 0.0, totalGreen = 0.0, totalBlue = 0.0, count = 0.0

        for x in 0..<side {
            for y in 0..<side {
                guard let pixel = representation.colorAt(x: x, y: y),
                      let rgb = pixel.usingColorSpace(.sRGB) else { continue }

                totalRed += Double(rgb.redComponent)
                totalGreen += Double(rgb.greenComponent)
                totalBlue += Double(rgb.blueComponent)
                count += 1

                // Prefer saturated, mid-brightness pixels: they read as "the album's colour"
                // far better than the darkest or lightest corner does.
                let brightness = Double(rgb.brightnessComponent)
                let score = Double(rgb.saturationComponent) * (1 - abs(brightness - 0.6))
                if score > bestScore {
                    bestScore = score
                    best = rgb
                }
            }
        }

        guard count > 0 else { return .fallback }

        let averageRed = totalRed / count
        let averageGreen = totalGreen / count
        let averageBlue = totalBlue / count
        let luminance = 0.299 * averageRed + 0.587 * averageGreen + 0.114 * averageBlue

        return ArtworkPalette(
            primary: Color(nsColor: best),
            secondary: Color(.sRGB, red: averageRed, green: averageGreen, blue: averageBlue),
            isLight: luminance > 0.6
        )
    }
}
