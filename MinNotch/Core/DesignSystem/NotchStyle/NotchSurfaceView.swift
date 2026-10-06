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

    /// The macOS 26 material, in the outline, so its edge light follows the notch's shape as the
    /// panel grows. A preview drawn offscreen cannot draw it and shows the style's own fill.
    @ViewBuilder
    private var liquidGlass: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(style.base.opacity(style.liquidTint)), in: edge)
                // Glass takes its appearance from its surroundings, which follow the system;
                // a light style over a dark Mac drew dark glass under dark text.
                .environment(\.colorScheme, style.isDark ? .dark : .light)
        } else {
            style.base
        }
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
