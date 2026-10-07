import AppKit
import SwiftUI

/// The fill of the notch's shape, in a style.
///
/// Drawn inside the surface's single clip (`NotchRootView.content`), so its edges are that clip's
/// edges and no second antialiased edge is laid over them. For Minimal Dark it is the black fill,
/// or the black fill under a material for Translucent Panel, exactly as before styles existed.
struct NotchSurfaceView<Edge: Shape>: View {
    let style: NotchSurfaceStyle
    /// Settings > Appearance > Translucent Panel, which only Minimal offers.
    let isTranslucent: Bool
    /// The outline for a border: the notch's, open at the top, or a window's.
    let edge: Edge
    /// False for a preview drawn offscreen, where an `NSVisualEffectView` cannot be drawn: glass
    /// keeps its tint, and nothing else needs a material.
    var drawsMaterials = true

    var body: some View {
        if style == .housing {
            // Before styles: one fill, or the fill under a material.
            if isTranslucent {
                ZStack {
                    Palette.notchFill
                    VisualEffectView(material: style.vibrancyMaterial, blendingMode: .withinWindow)
                        .opacity(0.55)
                }
            } else {
                Palette.notchFill
            }
        } else {
            styled
        }
    }

    private var styled: some View {
        ZStack {
            if style.liquidGlass, drawsMaterials {
                liquidGlass
            } else if let glass = style.glass {
                if drawsMaterials {
                    VisualEffectView(material: glass.material, blendingMode: .behindWindow)
                        .environment(\.colorScheme, glass.appearance == .darkAqua ? .dark : .light)
                    style.base.opacity(glass.tint)
                } else {
                    style.base.opacity(min(glass.tint + 0.35, 1))
                }
            } else {
                style.base
                if isTranslucent, drawsMaterials {
                    VisualEffectView(material: style.vibrancyMaterial, blendingMode: .withinWindow)
                        .opacity(0.55)
                }
            }
            if !style.gradient.isEmpty {
                LinearGradient(colors: style.gradient, startPoint: .top, endPoint: .bottom)
            }
            if style.grain > 0, !style.liquidGlass {
                NotchGrain.image
                    .resizable(resizingMode: .tile)
                    .opacity(style.grain)
            }
            if let border = style.border, !style.liquidGlass {
                // Centred on the outline and clipped by the surface, so half its width shows,
                // inside the edge.
                edge.stroke(
                    LinearGradient(colors: [border.top, border.bottom], startPoint: .top, endPoint: .bottom),
                    lineWidth: border.width * 2
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// Liquid Glass, in the outline, so it follows the notch's shape as the panel grows. A preview
    /// drawn offscreen cannot draw it and shows the style's own fill.
    @ViewBuilder
    private var liquidGlass: some View {
        if #available(macOS 26.0, *) {
            current(amount: style.liquidTint, clarity: 1 - style.liquidTint)
        } else {
            style.base
        }
    }

    /// What is behind, only lightly blurred, under a thick rim of Apple's glass that bends it at
    /// the edge, with a light dim (or, on a light style, a light wash) so text stays legible.
    /// Glass Opacity blurs it more and tints it towards the style, to nearly the solid style at 1;
    /// the dim, rim light and sheen fade as it rises.
    ///
    /// The road here, five rounds with the user: Apple's clear glass alone was all but invisible
    /// over a plain or dark window; its regular glass came out a smooth grey slab over dark ones;
    /// regular glass under a milky frost read as frosted plastic; clear glass with an edge and a
    /// sheen was still a grey slab over a dark window, because Apple's glass frosts in proportion
    /// to its size and at the panel's size blurs by about fifty points. Compared on screen over a
    /// dark and a bright test pattern, a six point blur under a fourteen point rim of Apple's glass
    /// was the only one that showed the window behind as a window, through glass with a thickness
    /// to it, with the notch's own text still legible.
    @available(macOS 26.0, *)
    private func current(amount: Double, clarity: Double) -> some View {
        let dark = style.isDark
        return ZStack {
            ClearGlassBackdrop(radius: 6 + 18 * amount)
            style.base.opacity(amount * 0.95)
            (dark ? Color.black.opacity(0.2 * clarity) : Color.white.opacity(0.35 * clarity))
            // The rim: Apple's glass along the edge, inside it, where it bends what is behind.
            Color.clear
                .glassEffect(.clear, in: GlassRim(edge: edge, width: 14))
                .opacity(0.4 + 0.6 * clarity)
            LinearGradient(
                stops: [.init(color: .white.opacity(0.12 * clarity), location: 0),
                        .init(color: .white.opacity(0.03 * clarity), location: 0.4),
                        .init(color: .clear, location: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GlassEdgeLight(edge: edge, strength: 0.25 + 0.55 * clarity)
        }
        // Glass takes its appearance from its surroundings, which follow the system; a light
        // style over a dark Mac drew dark glass under dark text.
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// A band along the outline, as wide as `width` either side of it; the surface's clip keeps the
/// inner half. The notch's outline is open at the top, so the band runs down the sides and along
/// the bottom, never across the top edge at the screen's.
private struct GlassRim<Edge: Shape>: Shape {
    let edge: Edge
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        edge.path(in: rect).strokedPath(StrokeStyle(lineWidth: width * 2, lineJoin: .round))
    }
}

/// Light caught by the edge of a sheet of glass: a bright line where the curve faces the light,
/// dimmer between, and a soft glow just inside it that gives the sheet a thickness.
private struct GlassEdgeLight<Edge: Shape>: View {
    let edge: Edge
    let strength: Double

    var body: some View {
        ZStack {
            edge.stroke(
                AngularGradient(
                    stops: [0.9, 0.15, 0.55, 0.15, 0.9, 0.15, 0.55, 0.15, 0.9].enumerated().map {
                        .init(color: .white.opacity($0.element * strength), location: Double($0.offset) / 8)
                    },
                    center: .center,
                    angle: .degrees(-30)
                ),
                lineWidth: 2.5
            )
            edge.stroke(.white.opacity(0.22 * strength), lineWidth: 14)
                .blur(radius: 7)
        }
        .allowsHitTesting(false)
    }
}

/// Fine noise, as a tile, for a surface with a material to it. Made once, from a fixed seed, so
/// two captures of the same style are the same.
@MainActor
enum NotchGrain {
    static let image: Image = {
        let size = 128
        var generator = SplitMix(seed: 0x6E6F7463)
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let value = UInt8(truncatingIfNeeded: generator.next() >> 56)
            // Grey noise, half light and half dark, around a transparent middle.
            let light = value > 127
            let strength = UInt8(abs(Int(value) - 128))
            bytes[i * 4] = light ? strength : 0
            bytes[i * 4 + 1] = light ? strength : 0
            bytes[i * 4 + 2] = light ? strength : 0
            bytes[i * 4 + 3] = strength
        }
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let cgImage = CGImage(
                  width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return Image(nsImage: NSImage()) }
        return Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: size / 2, height: size / 2)))
    }()

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}


