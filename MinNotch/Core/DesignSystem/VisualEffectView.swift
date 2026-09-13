import SwiftUI

/// SwiftUI wrapper around `NSVisualEffectView`.
///
/// SwiftUI's `.ultraThinMaterial` is fine inside a normal window, but the notch panel is
/// a borderless non-activating panel where we need explicit control over `blendingMode`
/// and `state` (materials stop updating in inactive windows unless state is `.active`).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
    }
}

extension View {
    /// Applies vibrancy behind the view, falling back to an opaque control colour when the
    /// user has turned blur off in Settings > Appearance (or when Reduce Transparency is on).
    func vibrantBackground(
        enabled: Bool,
        material: NSVisualEffectView.Material = .hudWindow,
        cornerRadius: CGFloat
    ) -> some View {
        background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            if enabled {
                VisualEffectView(material: material).clipShape(shape)
            } else {
                shape.fill(Palette.cardBackground)
            }
        }
    }
}
