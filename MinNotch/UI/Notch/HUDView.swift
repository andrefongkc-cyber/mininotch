import SwiftUI

/// The replacement volume, brightness, and keyboard backlight indicator.
///
/// Drawn inside the notch surface rather than in a window of its own, which is the whole
/// point of replacing the system overlay: the feedback appears where the hardware already
/// is instead of floating over the middle of whatever you are working on.
///
/// Like every other collapsed-state layout, content goes in the flanks either side of the
/// cutout, never in the middle where the camera housing is.
struct HUDView: View {
    let reading: HUDReading
    let geometry: NotchGeometry
    let style: HUDStyle
    let showsNumericValue: Bool
    let accent: Color

    /// Extra width claimed on each side of the cutout.
    static let flankWidth: CGFloat = 116

    static func width(for geometry: NotchGeometry) -> CGFloat {
        geometry.collapsedSize.width + flankWidth * 2
    }

    static func height(for geometry: NotchGeometry, style: HUDStyle) -> CGFloat {
        switch style {
        case .notchInline, .progressRing:
            return geometry.collapsedSize.height
        case .floatingPill:
            // Hangs below the cutout so the bar has room to be a real bar.
            return geometry.collapsedSize.height + 34
        }
    }

    var body: some View {
        switch style {
        case .notchInline:
            inline
        case .progressRing:
            ring
        case .floatingPill:
            pill
        }
    }

    // MARK: Styles

    /// Icon on the left flank, level bar on the right.
    private var inline: some View {
        HStack(spacing: 0) {
            icon
                .frame(width: Self.flankWidth, alignment: .trailing)
                .padding(.trailing, 10)

            Spacer(minLength: 0)
                .frame(width: geometry.collapsedSize.width)

            HStack(spacing: 7) {
                bar
                if showsNumericValue { valueLabel }
            }
            .frame(width: Self.flankWidth, alignment: .leading)
            .padding(.leading, 10)
        }
        .frame(
            width: Self.width(for: geometry),
            height: geometry.collapsedSize.height
        )
    }

    /// Icon on the left flank, a ring on the right.
    private var ring: some View {
        HStack(spacing: 0) {
            icon
                .frame(width: Self.flankWidth, alignment: .trailing)
                .padding(.trailing, 10)

            Spacer(minLength: 0)
                .frame(width: geometry.collapsedSize.width)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: clamped)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        // Trim starts at three o'clock; this puts zero at the top.
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                .animation(Motion.hover, value: clamped)

                if showsNumericValue { valueLabel }
            }
            .frame(width: Self.flankWidth, alignment: .leading)
            .padding(.leading, 10)
        }
        .frame(
            width: Self.width(for: geometry),
            height: geometry.collapsedSize.height
        )
    }

    /// A wide bar under the cutout, closest in shape to the system overlay it replaces.
    private var pill: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
                .frame(height: geometry.collapsedSize.height)

            HStack(spacing: 10) {
                icon
                bar
                if showsNumericValue { valueLabel }
            }
            .padding(.horizontal, 22)
            .frame(height: 34)
        }
        .frame(
            width: Self.width(for: geometry),
            height: Self.height(for: geometry, style: .floatingPill)
        )
    }

    // MARK: Pieces

    private var icon: some View {
        Image(systemName: reading.symbolName)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 18)
            .contentTransition(.symbolEffect(.replace))
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(reading.isMuted ? Color.white.opacity(0.4) : accent)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 4)
        .animation(Motion.hover, value: clamped)
    }

    private var valueLabel: some View {
        Text("\(reading.percentage)")
            .font(Typography.timecode)
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 24, alignment: .trailing)
    }

    private var clamped: Double { min(max(reading.value, 0), 1) }
}
