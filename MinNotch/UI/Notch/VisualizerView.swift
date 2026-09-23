import AppKit
import SwiftUI

/// The rhythm both the bars and the ambient glow move to.
///
/// Driven by playback state, not by the audio signal. Reading system sound needs a capture
/// tap and its own permission prompt, which is a poor trade for decoration, so this is an
/// animation that runs while something is playing and settles when it stops.
///
/// Both effects read from here so they visibly move together. Two independent animations at
/// similar speeds look broken in a way that one shared one does not.
enum VisualizerPulse {
    /// Periods are mutually non-repeating, so the pattern never visibly loops.
    static let periods: [Double] = [0.63, 0.91, 0.74, 1.13, 0.82]

    /// 0...1 for one channel of the pattern.
    static func level(index: Int, at time: TimeInterval, isPlaying: Bool) -> Double {
        guard isPlaying else { return 0 }
        let period = periods[index % periods.count]
        let phase = Double(index) * 1.7

        // Two waves per channel, so the motion does not read as a simple oscillation.
        let wave = sin(time / period + phase) * 0.5 + sin(time / (period * 0.41) + phase) * 0.5
        return min(max((wave + 2) / 4, 0), 1)
    }

    /// Average across channels, for effects that need one overall intensity.
    static func intensity(at time: TimeInterval, isPlaying: Bool) -> Double {
        guard isPlaying else { return 0 }
        let total = (0..<periods.count).reduce(0.0) { $0 + level(index: $1, at: time, isPlaying: true) }
        return total / Double(periods.count)
    }
}

/// Animated bars keyed to the album artwork's colours.
///
/// While the system audio tap is running (for the glow or for lyric matching) the bars follow
/// what is actually playing, through the same auto-gain, envelope and spring as the glow, so
/// they strike on the beat rather than sliding. Without it they run on the shared pulse. A
/// custom animated image replaces the bars entirely when one is chosen.
struct VisualizerView: View {
    var palette: ArtworkPalette
    var isPlaying: Bool
    var customImagePath: String?
    /// The running audio analyser, or nil to use the pulse.
    var audio: AudioAnalyzer?

    /// The bars' own shaping state, so they do not share a spring with the glow.
    @State private var dynamics = GlowDynamics()

    /// True when this view will draw the bars rather than a custom image. The card uses it to
    /// decide whether to lay a scrim under them: the bars need one, and someone's own animated
    /// image was chosen to be seen as it is.
    static func drawsBars(customImagePath: String?) -> Bool {
        guard let customImagePath else { return true }
        return NSImage(contentsOfFile: customImagePath) == nil
    }

    var body: some View {
        if let customImagePath, let image = NSImage(contentsOfFile: customImagePath) {
            AnimatedImageView(image: image, isAnimating: isPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        } else {
            bars
        }
    }

    private var bars: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let levels = heardLevels(at: time)

            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(Array(VisualizerPulse.periods.enumerated()), id: \.offset) { index, _ in
                    bar(height: height(index: index, at: time, heard: levels))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// One bar, in the cover's colours lifted to full strength.
    ///
    /// They used to be painted in `palette.primary` and `secondary` as sampled, which are the
    /// cover's own dominant colours and therefore the colours least likely to stand out
    /// against that cover: on a dark red sleeve the bars were dark red on dark red. Their
    /// black outline and shadow, meant to separate them from bright covers, disappeared into
    /// dark ones. Now the colours go through the same lift the ambient glow uses, so hue is
    /// kept but saturation and brightness have a floor, and the card lays a dark scrim under
    /// the bars so the area behind them is dark whatever the cover is. Against a guaranteed
    /// dark ground a bright bar needs a light rim, not a dark one.
    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [palette.glowPrimary, palette.glowSecondary],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .frame(width: 4, height: height)
            .shadow(color: palette.glowPrimary.opacity(0.55), radius: 2)
    }

    /// One level per bar from the analyser, low frequencies on the left, or nil without it.
    ///
    /// The analyser has more bands than there are bars, so neighbouring bands are averaged into
    /// each bar. Shaped here rather than read raw: a band's raw level wanders around the middle
    /// of its range and never leaps, which is the same flat motion the glow had before it went
    /// through `GlowDynamics`.
    private func heardLevels(at time: TimeInterval) -> [Double]? {
        guard isPlaying, let analysis = audio?.current, !analysis.bands.isEmpty else { return nil }
        let barCount = VisualizerPulse.periods.count
        let bands = analysis.bands
        let grouped: [Double] = (0..<barCount).map { bar in
            let start = bar * bands.count / barCount
            let end = max(start + 1, (bar + 1) * bands.count / barCount)
            let slice = bands[start..<min(end, bands.count)]
            return slice.reduce(0, +) / Double(slice.count)
        }
        let shaped = dynamics.shape(
            GlowDynamics.Levels(energy: analysis.energy, bands: grouped, beat: analysis.beat),
            at: time
        )
        return shaped.bands
    }

    private func height(index: Int, at time: TimeInterval, heard: [Double]?) -> CGFloat {
        let minimum: CGFloat = 3
        let maximum: CGFloat = 18
        guard isPlaying else { return minimum + 1 }
        let level = heard.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            ?? VisualizerPulse.level(index: index, at: time, isPlaying: isPlaying)
        return minimum + (maximum - minimum) * CGFloat(min(max(level, 0), 1))
    }
}

/// Plays an animated image, so a user-supplied GIF or APNG actually animates.
///
/// SwiftUI's `Image` renders only the first frame of an animated file. `NSImageView` plays
/// them, which is why this drops down to AppKit for what looks like it should be one line.
struct AnimatedImageView: NSViewRepresentable {
    var image: NSImage
    var isAnimating: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = isAnimating
        view.image = image
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
        view.animates = isAnimating
    }
}
