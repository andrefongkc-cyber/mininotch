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
/// A custom animated image replaces the bars entirely when one is chosen.
struct VisualizerView: View {
    var palette: ArtworkPalette
    var isPlaying: Bool
    var customImagePath: String?

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

            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(Array(VisualizerPulse.periods.enumerated()), id: \.offset) { index, _ in
                    bar(height: height(index: index, at: time))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
    }

    /// Each bar carries its own dark outline and drop shadow.
    ///
    /// The bars sit on top of album art, which can be any colour including near-white, and a
    /// plain coloured bar disappears against a bright cover. The outline gives every bar an
    /// edge regardless of what is behind it.
    private func bar(height: CGFloat) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [palette.primary, palette.secondary],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .overlay(
                Capsule().strokeBorder(Color.black.opacity(0.55), lineWidth: 0.75)
            )
            .frame(width: 4, height: height)
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 0.5)
    }

    private func height(index: Int, at time: TimeInterval) -> CGFloat {
        let minimum: CGFloat = 3
        let maximum: CGFloat = 18
        let level = VisualizerPulse.level(index: index, at: time, isPlaying: isPlaying)
        guard isPlaying else { return minimum + 1 }
        return minimum + (maximum - minimum) * CGFloat(level)
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
