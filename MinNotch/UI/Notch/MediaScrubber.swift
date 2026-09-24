import SwiftUI

/// Playback position bar.
///
/// Written by hand rather than using `Slider` because the notch needs a much thinner track
/// than the system control, a thumb that only appears on hover, and a read-only mode for
/// sources that cannot seek. It still behaves like a slider: click to jump, drag to scrub,
/// and the value only commits when the drag ends.
struct MediaScrubber: View {
    /// 0...1.
    var progress: Double
    var tint: Color
    /// False for sources with no seek command, which renders as a progress bar.
    var isSeekable: Bool
    var onScrubStateChange: (Bool) -> Void
    var onCommit: (Double) -> Void
    /// Called on every step of a drag, for a value that should follow the pointer rather than
    /// land when it is let go, such as a volume.
    var onChange: ((Double) -> Void)? = nil

    @State private var isHovering = false
    @State private var dragFraction: Double?

    private var displayed: Double { dragFraction ?? progress }
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let filled = width * min(max(displayed, 0), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: max(filled, 0), height: trackHeight)

                if isSeekable && (isHovering || dragFraction != nil) {
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .offset(x: max(filled - 4.5, -4.5))
                }
            }
            .frame(height: 14)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isSeekable, width > 0 else { return }
                        if dragFraction == nil { onScrubStateChange(true) }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        dragFraction = fraction
                        onChange?(fraction)
                    }
                    .onEnded { value in
                        guard isSeekable, width > 0 else { return }
                        let fraction = min(max(value.location.x / width, 0), 1)
                        dragFraction = nil
                        onScrubStateChange(false)
                        onCommit(fraction)
                    }
            )
        }
        .frame(height: 14)
        .animation(Motion.hover, value: isHovering)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(Int(displayed * 100)) percent")
    }
}

/// Formats a playback position as "3:42", or "1:03:42" for anything over an hour.
enum TimeFormat {
    static func string(from interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let total = Int(interval.rounded())
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
