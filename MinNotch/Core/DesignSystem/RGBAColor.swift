import SwiftUI

/// A `Codable` colour, so a user-chosen accent survives export/import of the settings file.
///
/// SwiftUI's `Color` is not `Codable` and `NSColor` archives to opaque data, so the
/// settings model stores plain sRGB components instead.
struct RGBAColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        self.init(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent),
            alpha: Double(ns.alphaComponent)
        )
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    static let systemBlue = RGBAColor(red: 0.0, green: 0.478, blue: 1.0)
}
