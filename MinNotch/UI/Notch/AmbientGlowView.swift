import SwiftUI

/// Renders one glow, for one placement.
///
/// Drawn as stroked `Shape`s rather than into a `Canvas`. Canvas would be cheaper for the
/// number of segments involved, but its output does not appear in an AppKit layer capture,
/// which is the only way this project can verify what the notch actually draws. A renderer
/// nobody can check is worse than one that costs a few more views, so segment counts are
/// kept low instead.
///
/// Two passes: a wide blurred one that is the spill, and a narrow crisp one that is the
/// filament. Together they read as light rather than as a thick coloured border.
struct AmbientGlowView: View {
    /// The outline this glow traces.
    var outline: GlowOutline
    var settings: AmbientGlowSettings
    var palette: ArtworkPalette
    var isPlaying: Bool
    /// Live analysis, or nil when audio-reactive is off or not yet delivering.
    var audio: AudioAnalyzer?
    /// Prints the raw and shaped levels over the glow, for tuning the envelope and spring by
    /// eye instead of guessing at the constants. Follows Settings > Advanced > debug overlay.
    var showsLevelReadout: Bool = false
    /// The size the outline is settling at, used only to cap the blur.
    ///
    /// Not the size the outline is drawn at. That comes from layout, through `GlowStroke`,
    /// which is re-pathed at the rect it is actually rendered in on every frame of the surface
    /// animation. This is a hint for one cap, where being the destination rather than the
    /// in-between size does no harm.
    var sizeHint: CGSize
    /// How far outside the outline this glow is allowed to spread, in points.
    ///
    /// `drawingGroup()` rasterises into a layer the size of this view, so a blur cannot
    /// reach past its own bounds: without room to spread, the falloff is sliced off
    /// mid-gradient and the glow ends on a hard edge exactly where the view does. Against
    /// the desktop that edge is not read as light at all, but as a translucent strip beside
    /// the panel. The caller states how much room it can give and the blur is capped to
    /// half of it, so the light always reaches nothing before the layer runs out.
    ///
    /// Zero means "no room", which is correct for a glow drawn inside a laid-out box.
    var spill: CGFloat = 0
    /// False while the glow is switched off for the state the notch is in.
    ///
    /// Hidden rather than removed, so the view stays in place and follows the surface when the
    /// notch opens or closes; see the note at the notch call site. Hidden also pauses the
    /// timeline, so a glow waiting behind a closed notch all day is a still, transparent layer
    /// that costs nothing, not an animation running at zero opacity.
    var isVisible: Bool = true

    /// The envelope, gain, and spring state for this glow.
    ///
    /// One per drawn glow, because the spring is stateful and two placements on screen at
    /// once must not share a velocity. Held as a reference type and stepped inside the
    /// timeline body rather than published as observable state: the timeline already redraws
    /// every frame, so invalidating the view on top of that would be a second redraw for the
    /// same information.
    @State private var dynamics = GlowDynamics()

    var body: some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: !isAnimating || !isVisible)) { context in
            let input = makeInput(at: context.date)
            let segments = AmbientGlowStyleFactory.make(settings.style).segments(input: input)

            ZStack {
                strokes(segments, widthScale: 1.6)
                    // The spill breathes with the level too. A blur that stays the same
                    // width while the stroke inside it grows reads as the stroke getting
                    // fatter; a blur that swells with it reads as more light.
                    .blur(radius: blurRadius(for: sizeHint, level: input.energy))

                strokes(segments, widthScale: 0.45)
                    .blur(radius: 1)
                    .opacity(0.9)
            }
            // Flattens the whole stack into one layer before compositing. Without it the
            // blur is recomposited per stroked shape every frame, which is what dragged
            // the rest of the interface down while the glow was running.
            .drawingGroup()
            // Bottom trailing, because the surface's own debug outline already puts its
            // geometry summary at the bottom leading and the two overlapped.
            .overlay(alignment: .bottomTrailing) {
                // Clear of the frame edge by more than the shape's shoulder inset, so the
                // text sits over the fill rather than over the transparent shoulder band.
                levelReadout.padding(spill + 14)
            }
        }
        // Grows the layer past the thing it decorates by the spill on every side. Negative
        // padding enlarges what the content is offered and keeps it centred on the caller's
        // frame, which a `GeometryReader` or an explicit frame did not: one aligned the layer
        // top-leading, the other pinned it to the destination size.
        .padding(-spill)
        // Animated by the surface's own spring, since `isVisible` changes in the same update as
        // the open or closed state.
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// Strokes one pass of the segments.
    ///
    /// Each stretch is a `GlowStroke` shape rather than a `Path` built here. A `Path` is a
    /// value computed once from whatever size this body was told, and the only size a body
    /// can be told mid-animation is the destination: that is why the glow used to jump to the
    /// fully open outline while the fill behind it was still growing. A `Shape` is asked for
    /// its path at render time, at the rect it is actually being drawn in, which during the
    /// surface's spring is the in-between rect. It is the same reason the fill's own clip
    /// shape has always tracked the box.
    private func strokes(_ segments: [GlowSegment], widthScale: CGFloat) -> some View {
        ZStack {
            ForEach(segments) { segment in
                if segment.coversWholePath {
                    // Stroking the closed path directly, rather than a trim from 0 to 1.
                    // A trim is an open stroke, so it gets a round cap at each end and the
                    // two overlap at the seam. On a shape as small as the closed pill that
                    // overlap is a visible bright spot, which is most of what made the
                    // closed glow look uneven.
                    GlowStroke(outline: outline, inset: spill, trim: nil)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: segment.width * widthScale))
                } else {
                    ForEach(Array(wrap(segment).enumerated()), id: \.offset) { _, range in
                        GlowStroke(outline: outline, inset: spill, trim: range)
                            .stroke(
                                segment.color,
                                style: StrokeStyle(lineWidth: segment.width * widthScale, lineCap: .round)
                            )
                    }
                }
            }
        }
    }

    /// Splits a segment that runs past the end of the path.
    ///
    /// `trimmedPath` does not wrap, so a range crossing the seam is silently clipped unless
    /// it is drawn as two pieces. Handling it here means no style has to know the seam exists.
    private func wrap(_ segment: GlowSegment) -> [ClosedRange<CGFloat>] {
        var start = segment.start.truncatingRemainder(dividingBy: 1)
        if start < 0 { start += 1 }
        let length = max(segment.end - segment.start, 0.0005)
        let end = start + length

        guard end > 1 else {
            return [CGFloat(start)...CGFloat(min(end, 1))]
        }
        return [
            CGFloat(start)...1,
            0...CGFloat(min(end - 1, 1))
        ]
    }

    /// Blur is capped against the shape's smaller dimension and the room the caller gave,
    /// then rides the level.
    ///
    /// The closed pill is barely thirty points tall, and a blur wider than that smears the
    /// top and bottom edges into each other, leaving the middle washed out while the corners,
    /// where more of the outline runs through the same area, stay bright.
    private func blurRadius(for size: CGSize, level: Double) -> CGFloat {
        var limit = max(min(size.width, size.height) * 0.3, 3)
        // Half the spill, so the falloff has finished by the time the layer's edge arrives.
        // A caller that offers no room keeps the old behaviour rather than losing its glow.
        if spill > 0 { limit = min(limit, spill / 2) }

        let peak = min(CGFloat(settings.glowRadius), limit)
        // Rides the level but never exceeds the peak, so the spill budget promised above
        // still holds at the loudest moment of the loudest track.
        return peak * (0.5 + 0.5 * CGFloat(min(max(level, 0), 1)))
    }

    /// Every frame the display draws, while something is playing.
    ///
    /// Throttling is half of why a reactive effect feels late: the envelope can be right and
    /// the spring correct, and a 30 Hz sample of them still arrives quantised and behind the
    /// sound. `nil` is the display's own rate.
    ///
    /// It was worth checking what that costs, and the answer is nothing, which is not the
    /// answer it looked like it would be. Capped at 15, 30, and 60 the panel measured the
    /// same, within noise, and so did one segment against sixteen, a pill-sized layer
    /// against a panel-sized one, and the blur and `drawingGroup()` switched off entirely.
    /// What actually costs is that anything animating over the notch re-renders the whole
    /// surface every display frame, whatever it is: the media card's own visualizer does it
    /// with the glow switched off. That is a pre-existing cost and a separate problem, and
    /// throttling this timeline does not touch it, so there is nothing to buy by throttling.
    ///
    /// Idle is still slow-ticked. There is nothing to be late for with nothing playing.
    private var frameInterval: Double? {
        isPlaying ? nil : 1.0 / 12
    }

    /// A static colour sitting still needs no frames at all.
    private var isAnimating: Bool {
        if isPlaying { return true }
        return !(settings.style == .pulse && settings.colorMode == .staticColor)
    }

    /// Reads whichever source is available and shapes it.
    ///
    /// Both sources go through the same chain on purpose. What a style receives is the same
    /// kind of number either way, so the motion can be tuned, and judged, on a machine where
    /// the system audio permission cannot be granted at all.
    private func makeInput(at date: Date) -> GlowInput {
        let time = date.timeIntervalSinceReferenceDate

        let raw: GlowDynamics.Levels
        if let analysis = audio?.current {
            raw = GlowDynamics.Levels(
                energy: analysis.energy,
                bands: analysis.bands,
                beat: analysis.beat
            )
        } else {
            raw = GlowFallbackSource.levels(at: time, isPlaying: isPlaying, speed: settings.speed)
        }

        let shaped = dynamics.shape(raw, at: time)

        return GlowInput(
            time: time,
            energy: shaped.energy,
            bands: shaped.bands,
            beat: shaped.beat,
            isPlaying: isPlaying,
            palette: palette,
            colorMode: settings.style.usesColorMode ? settings.colorMode : .rainbow,
            staticColor: settings.staticColor.color,
            intensity: settings.intensity,
            speed: settings.speed
        )
    }

    // MARK: Tuning readout

    /// Raw levels above shaped ones, so the envelope, the gain, and the spring can be seen
    /// doing their work rather than guessed at.
    ///
    /// The constants in `GlowDynamics.Tuning` are the whole feel of the effect and there is
    /// no way to judge them from the glow alone: a value that never leaves the middle of its
    /// range and a value that is pinned at the top look much the same once blurred.
    @ViewBuilder
    private var levelReadout: some View {
        if showsLevelReadout {
            let raw = dynamics.raw
            let shaped = dynamics.shaped
            let rate = dynamics.frameInterval > 0 ? 1 / dynamics.frameInterval : 0

            VStack(alignment: .leading, spacing: 0) {
                Text("raw \(Self.meter(raw.bands))  e\(Self.number(raw.energy))")
                Text("out \(Self.meter(shaped.bands))  e\(Self.number(shaped.energy))")
                Text("beat\(Self.number(shaped.beat))  \(Int(rate.rounded()))fps  \(audio == nil ? "fallback" : "audio")")
            }
            .font(.system(size: 8, weight: .medium).monospaced())
            .foregroundStyle(Color(nsColor: .systemGreen))
            .padding(3)
            .background(Color.black.opacity(0.7))
            .allowsHitTesting(false)
        }
    }

    /// Eight levels as one string of block characters, which is far quicker to read at a
    /// glance than eight numbers and fits where eight numbers would not.
    private static func meter(_ levels: [Double]) -> String {
        let blocks = Array(" ▁▂▃▄▅▆▇█")
        guard !levels.isEmpty else { return String(repeating: " ", count: GlowInput.bandCount) }
        return String(levels.map { level in
            let index = Int((min(max(level, 0), 1) * Double(blocks.count - 1)).rounded())
            return blocks[index]
        })
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// The outline a glow traces, as a value rather than a closure.
///
/// A value, so it can live inside a `Shape` and be re-pathed at render time. The corner radius
/// is the one number that changes between the closed pill and the open panel besides the size,
/// so it is the animatable part.
struct GlowOutline: Equatable {
    enum Kind: Equatable {
        /// The notch outline, with its concave shoulders.
        case notch(shoulderRadius: CGFloat)
        /// A plain rounded rectangle, for the Settings preview.
        case roundedRect
    }

    var kind: Kind
    /// The bottom corner radius for the notch, or the corner radius for a rounded rectangle.
    var radius: CGFloat

    static func notch(_ shape: NotchShape) -> GlowOutline {
        GlowOutline(kind: .notch(shoulderRadius: shape.shoulderRadius), radius: shape.bottomRadius)
    }

    static func roundedRect(cornerRadius: CGFloat) -> GlowOutline {
        GlowOutline(kind: .roundedRect, radius: cornerRadius)
    }

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .notch(let shoulderRadius):
            return NotchShape(shoulderRadius: shoulderRadius, bottomRadius: radius).path(in: rect)
        case .roundedRect:
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
    }
}

/// One stroked stretch of a glow's outline, pathed at the rect it is drawn in.
///
/// The rect is the whole padded layer, so the outline is inset by the spill before it is
/// traced, which puts it back on the edge of the thing being decorated.
struct GlowStroke: Shape {
    var outline: GlowOutline
    var inset: CGFloat
    var trim: ClosedRange<CGFloat>?

    var animatableData: CGFloat {
        get { outline.radius }
        set { outline.radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let full = outline.path(in: rect.insetBy(dx: inset, dy: inset))
        guard let trim else { return full }
        return full.trimmedPath(from: trim.lowerBound, to: trim.upperBound)
    }
}
