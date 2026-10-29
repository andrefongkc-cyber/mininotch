import SwiftUI

/// What Aurora draws with right now: the colours, and whether they drift.
struct NotchAuroraState: Equatable {
    /// Three colours, lifted to be visible as light. Teal, violet and magenta with nothing playing.
    var colors: [Color] = NotchAuroraState.defaultColors
    /// Drifting only while the panel is open and something is playing, and never under Reduce
    /// Motion. Still, it costs nothing: the timeline is paused and draws one frame.
    var moves = false
    /// The band along the edge. Off while Ambient Lighting lights that edge, so the two are not
    /// doubled; the fill behind the content stays either way.
    var drawsEdge = true

    static let defaultColors: [Color] = [
        Color(red: 0.10, green: 0.85, blue: 0.78),
        Color(red: 0.52, green: 0.30, blue: 0.98),
        Color(red: 0.95, green: 0.25, blue: 0.70),
    ]

    static let still = NotchAuroraState()

    /// The colours of what is playing, through `glowPrimary` and `glowSecondary` so a muted cover
    /// is still visible, with a third between them; the defaults when nothing is.
    static func colors(for palette: ArtworkPalette?) -> [Color] {
        guard let palette else { return defaultColors }
        return [palette.glowPrimary, defaultColors[1], palette.glowSecondary]
    }
}

/// Aurora's fill: soft, heavily blurred bands of colour inside the panel, and one along its edge.
///
/// Shapes, not a `Canvas`, so `--capture-notch` draws it. Flattened with `drawingGroup` into a
/// layer padded by the blur's reach, so the blur fades out inside the layer rather than ending on
/// its edge; the surface's single clip then cuts it to the notch. The drift is slow, about one
/// pass every half minute, so fifteen frames a second is plenty; while still, the timeline is
/// paused and the bands hold exactly where they were, never jumping when they start again.
struct NotchAuroraLayer<Edge: Shape>: View {
    let strength: Double
    let state: NotchAuroraState
    let edge: Edge

    /// The drift's clock, which only runs while it moves: paused, it holds; resumed, it carries on
    /// from where it held rather than from the wall clock.
    @State private var heldAt: TimeInterval = 0
    @State private var resumedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !state.moves)) { context in
            GeometryReader { proxy in
                bands(at: time(at: context.date), in: proxy.size)
            }
        }
        .onChange(of: state.moves, initial: true) { _, moves in
            if moves {
                resumedAt = Date()
            } else {
                heldAt = time(at: Date())
                resumedAt = nil
            }
        }
        .allowsHitTesting(false)
    }

    private func time(at date: Date) -> TimeInterval {
        guard let resumedAt else { return heldAt }
        return heldAt + date.timeIntervalSince(resumedAt)
    }

    private func bands(at t: TimeInterval, in size: CGSize) -> some View {
        let shortSide = max(min(size.width, size.height), 1)
        let blur = min(max(shortSide * 0.32, 8), 44)
        let room = blur * 2
        let colors = state.colors.count >= 3 ? state.colors : NotchAuroraState.defaultColors

        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let phase = Double(index) * 2.1
                let period = 26.0 + Double(index) * 7
                let x = 0.5 + 0.34 * sin(t * 2 * .pi / period + phase)
                let y = 0.62 + 0.22 * cos(t * 2 * .pi / (period * 1.3) + phase)
                Ellipse()
                    .fill(colors[index].opacity(strength))
                    .frame(width: size.width * 0.62, height: size.height * 0.75)
                    .position(x: size.width * x, y: size.height * y)
            }
            if state.drawsEdge {
                edge.stroke(
                    AngularGradient(
                        colors: colors + [colors[0]],
                        center: .center,
                        angle: .degrees(t * 360 / 40)
                    ),
                    lineWidth: min(10, shortSide * 0.12)
                )
                .opacity(strength * 1.1)
            }
        }
        .frame(width: size.width, height: size.height)
        .padding(room)
        .blur(radius: blur)
        .drawingGroup()
        .padding(-room)
    }
}
