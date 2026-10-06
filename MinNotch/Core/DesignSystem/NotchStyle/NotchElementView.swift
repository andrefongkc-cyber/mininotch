import SwiftUI

/// Which of a style's element treatments to draw.
enum NotchElementRole {
    case tile
    case button
    case module
    case groove
    case transport
    case primaryTransport
}

/// The outline of an element.
enum NotchElementShape: Equatable {
    case rounded(CGFloat, RoundedCornerStyle = .continuous)
    case capsule
    case circle
}

/// A background element in the current style: a row, a button's highlight, a module, a groove.
///
/// Placed with `.background(...)`, so it never changes layout. `emphasis` is the opacity the call
/// site always filled itself with in white (0.05 for a resting row, 0.1 hovered, 0 for an idle
/// button); a plain style draws exactly that, and the others read it as how much to light up.
///
/// Shadows are blurred shapes flattened with `drawingGroup`, with room around them to fade in,
/// because a layer filter's blur or shadow does not appear in `--capture-notch`, which is how
/// every style is reviewed.
struct NotchElementView: View {
    @Environment(\.notchStyle) private var theme

    let role: NotchElementRole
    var shape: NotchElementShape = .rounded(6)
    let emphasis: Double

    init(_ role: NotchElementRole, shape: NotchElementShape = .rounded(6), emphasis: Double) {
        self.role = role
        self.shape = shape
        self.emphasis = emphasis
    }

    private var element: NotchElementStyle? {
        switch role {
        case .tile: return theme.tile
        case .button: return theme.button
        case .module: return theme.module
        case .groove: return theme.track.groove
        case .transport: return theme.transport.disc
        case .primaryTransport: return theme.transport.primaryDisc ?? theme.transport.disc
        }
    }

    var body: some View {
        if let element, emphasis > 0 || element.drawsWhenIdle {
            if element.isPlain, case .ink = element.fill {
                // Exactly the view Minimal always drew, so nothing about it can drift.
                plainFill(theme.ink.opacity(emphasis))
            } else {
                styled(element)
            }
        }
    }

    // MARK: Drawing

    @ViewBuilder
    private func plainFill(_ color: Color) -> some View {
        switch shape {
        case .rounded(let radius, let style):
            RoundedRectangle(cornerRadius: radius, style: style).fill(color)
        case .capsule:
            Capsule().fill(color)
        case .circle:
            Circle().fill(color)
        }
    }

    private func styled(_ element: NotchElementStyle) -> some View {
        let outline = ElementOutline(shape: shape, cornerScale: element.cornerScale)
        let room = element.outer.map { $0.radius * 2 + max(abs($0.x), abs($0.y)) }.max() ?? 0

        return ZStack {
            if !element.outer.isEmpty {
                ZStack {
                    ForEach(Array(element.outer.enumerated()), id: \.offset) { _, shadow in
                        outline
                            .fill(shadow.color)
                            .offset(x: shadow.x, y: shadow.y)
                            .blur(radius: shadow.radius)
                    }
                }
                .padding(room)
                .drawingGroup()
                .padding(-room)
                .allowsHitTesting(false)
            }

            fill(element, outline: outline)
                .overlay {
                    if !element.inner.isEmpty {
                        ZStack {
                            ForEach(Array(element.inner.enumerated()), id: \.offset) { _, shadow in
                                outline
                                    .stroke(shadow.color, lineWidth: shadow.radius * 2)
                                    .offset(x: shadow.x, y: shadow.y)
                                    .blur(radius: shadow.radius)
                            }
                        }
                        .clipShape(outline)
                        .drawingGroup()
                    }
                }
                .overlay {
                    if let border = element.border {
                        outline.strokeBorder(
                            LinearGradient(colors: [border.top, border.bottom], startPoint: .top, endPoint: .bottom),
                            lineWidth: border.width
                        )
                    }
                }
        }
    }

    @ViewBuilder
    private func fill(_ element: NotchElementStyle, outline: ElementOutline) -> some View {
        switch element.fill {
        case .ink:
            outline.fill(theme.ink.opacity(emphasis))
        case .color(let color, let lift):
            outline.fill(color)
                .overlay(outline.fill(theme.ink.opacity(emphasis * lift)))
        case .gradient(let top, let bottom, let lift):
            outline.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                .overlay(outline.fill(theme.ink.opacity(emphasis * lift)))
        }
    }
}

/// `NotchElementShape` as an insettable `Shape`, with a style's corner scale applied.
struct ElementOutline: InsettableShape {
    let shape: NotchElementShape
    var cornerScale: CGFloat = 1
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        switch shape {
        case .rounded(let radius, let style):
            let scaled = min(max(radius * cornerScale - inset, 0), min(rect.width, rect.height) / 2)
            return RoundedRectangle(cornerRadius: scaled, style: style).path(in: rect)
        case .capsule:
            return Capsule().path(in: rect)
        case .circle:
            return Circle().path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> ElementOutline {
        var copy = self
        copy.inset += amount
        return copy
    }
}
