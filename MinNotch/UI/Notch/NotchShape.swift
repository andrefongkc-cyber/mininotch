import SwiftUI

/// The notch outline: square against the top edge of the display, rounded at the bottom,
/// with a concave fillet on each upper corner.
///
/// The fillets are what make the surface read as part of the hardware rather than as a
/// floating window. They flare outward into the menu bar, so the join between the black
/// pill and the black menu bar has no visible corner. The body is inset by the shoulder
/// radius on both sides, so `contentInset` is what callers should pad their content by.
struct NotchShape: Shape {
    var shoulderRadius: CGFloat = Metrics.notchShoulderRadius
    var bottomRadius: CGFloat = Metrics.notchPanelCornerRadius

    /// Animate corner changes when the panel expands.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, bottomRadius) }
        set {
            shoulderRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    var contentInset: CGFloat { shoulderRadius }

    func path(in rect: CGRect) -> Path {
        let shoulder = min(shoulderRadius, rect.width / 2)
        let bottom = min(bottomRadius, max(rect.width / 2 - shoulder, 0), rect.height)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Concave fillet into the left edge of the body.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder),
            control: CGPoint(x: rect.minX + shoulder, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + shoulder, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - shoulder - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
