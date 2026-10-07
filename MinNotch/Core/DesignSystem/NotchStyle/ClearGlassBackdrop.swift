import AppKit
import SwiftUI

/// What is behind the window, blurred by `radius` points: the body of Liquid Glass.
///
/// Apple's own glass frosts in proportion to its size, and a panel the notch's size came out a
/// smooth wash of colour with nothing behind it recognisable: the user's open panel over a dark
/// window was a grey slab, and they asked for it "more glassy" twice. No public API sets a blur
/// radius, so this is `NSVisualEffectView` with its blur turned down. Its backdrop layer carries
/// filters named `gaussianBlur` (radius 30 for `.hudWindow`) and `colorSaturate`, set here through
/// Core Animation's public `filters.<name>.<key>` key paths, and its fill and tone layers, the
/// material's own tint, are hidden. Each is checked before it is touched; on a macOS laid out
/// differently, what is left is the ordinary HUD material, which is frosted but still glass.
struct ClearGlassBackdrop: NSViewRepresentable {
    var radius: Double
    var saturation: Double = 1.4

    func makeNSView(context: Context) -> ClearGlassBackdropView {
        let view = ClearGlassBackdropView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // A non-activating panel is never key, and an inactive material stops following
        // what is behind it.
        view.state = .active
        view.radius = radius
        view.saturation = saturation
        return view
    }

    func updateNSView(_ view: ClearGlassBackdropView, context: Context) {
        view.radius = radius
        view.saturation = saturation
        view.applyClarity()
    }
}

final class ClearGlassBackdropView: NSVisualEffectView {
    var radius: Double = 6
    var saturation: Double = 1.4

    // The material rebuilds its layers when its window, appearance or scale changes, so the
    // settings go back on after each.
    override func updateLayer() {
        super.updateLayer()
        applyClarity()
    }

    override func layout() {
        super.layout()
        applyClarity()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyClarity()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyClarity()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyClarity()
    }

    func applyClarity() {
        guard let root = layer else { return }
        apply(to: root)
    }

    private func apply(to layer: CALayer) {
        switch layer.name {
        case "backdrop":
            set(radius, filter: "gaussianBlur", input: "inputRadius", on: layer)
            set(saturation, filter: "colorSaturate", input: "inputAmount", on: layer)
        case "fill", "tone", "desktop tint":
            if !layer.isHidden { layer.isHidden = true }
        default:
            break
        }
        layer.sublayers?.forEach(apply)
    }

    private func set(_ value: Double, filter name: String, input: String, on layer: CALayer) {
        guard let filter = layer.filters?.first(where: { ($0 as AnyObject).value(forKey: "name") as? String == name }),
              let inputs = (filter as AnyObject).value(forKey: "inputKeys") as? [String],
              inputs.contains(input)
        else { return }
        let keyPath = "filters.\(name).\(input)"
        if (layer.value(forKeyPath: keyPath) as? Double) != value {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setValue(value, forKeyPath: keyPath)
            CATransaction.commit()
        }
    }
}
