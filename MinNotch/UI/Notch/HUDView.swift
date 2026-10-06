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
    @Environment(\.notchStyle) private var theme
    let reading: HUDReading
    let geometry: NotchGeometry
    let style: HUDStyle
    let showsNumericValue: Bool
    let accent: Color

    /// Extra width claimed on each side of the cutout by the inline and ring styles, which put
    /// the icon on one side and the level on the other. It was 116, which made a volume change
    /// stretch the notch most of the way across the menu bar; reported as "really big".
    static let flankWidth: CGFloat = 80
    /// How far the bar below the notch reaches past the cutout on each side. It sits under the
    /// cutout rather than beside it, so it needs no flanks of its own, only a little overhang.
    static let pillOverhang: CGFloat = 36
    /// Height of the bar below the notch. Only the width was too much; this stays.
    static let pillHeight: CGFloat = 34

    static func width(for geometry: NotchGeometry, style: HUDStyle) -> CGFloat {
        switch style {
        case .notchInline, .progressRing:
            return geometry.collapsedSize.width + flankWidth * 2
        case .floatingPill:
            return geometry.collapsedSize.width + pillOverhang * 2
        }
    }

    static func height(for geometry: NotchGeometry, style: HUDStyle) -> CGFloat {
        switch style {
        case .notchInline, .progressRing:
            return geometry.collapsedSize.height
        case .floatingPill:
            // Hangs below the cutout so the bar has room to be a real bar.
            return geometry.collapsedSize.height + pillHeight
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
                .padding(.trailing, 8)
                .frame(width: Self.flankWidth, alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: geometry.collapsedSize.width)

            HStack(spacing: 6) {
                bar
                if showsNumericValue { valueLabel }
            }
            .padding(.leading, 8)
            .padding(.trailing, Metrics.notchShoulderRadius + 4)
            .frame(width: Self.flankWidth, alignment: .leading)
        }
        .frame(
            width: Self.width(for: geometry, style: .notchInline),
            height: geometry.collapsedSize.height
        )
    }

    /// Icon on the left flank, a ring on the right.
    private var ring: some View {
        HStack(spacing: 0) {
            icon
                .padding(.trailing, 8)
                .frame(width: Self.flankWidth, alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: geometry.collapsedSize.width)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(theme.ink.opacity(0.18), lineWidth: 3)
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
            .padding(.leading, 8)
            .frame(width: Self.flankWidth, alignment: .leading)
        }
        .frame(
            width: Self.width(for: geometry, style: .progressRing),
            height: geometry.collapsedSize.height
        )
    }

    /// A wide bar under the cutout, closest in shape to the system overlay it replaces.
    private var pill: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
                .frame(height: geometry.collapsedSize.height)

            HStack(spacing: 8) {
                icon
                bar
                if showsNumericValue { valueLabel }
            }
            .padding(.horizontal, 14)
            .frame(height: Self.pillHeight)
        }
        .frame(
            width: Self.width(for: geometry, style: .floatingPill),
            height: Self.height(for: geometry, style: .floatingPill)
        )
    }

    // MARK: Pieces

    private var icon: some View {
        Image(systemName: reading.symbolName)
            .font(.system(size: 13))
            .foregroundStyle(theme.ink.opacity(0.9))
            .frame(width: 18)
            .contentTransition(.symbolEffect(.replace))
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                NotchElementView(.groove, shape: .capsule, emphasis: 0.18)
                NotchTrackFill(color: reading.isMuted ? theme.ink.opacity(0.4) : accent)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 4)
        .animation(Motion.hover, value: clamped)
    }

    private var valueLabel: some View {
        Text("\(reading.percentage)")
            .font(Typography.timecode)
            .foregroundStyle(theme.ink.opacity(0.85))
            .frame(width: 24, alignment: .trailing)
    }

    private var clamped: Double { min(max(reading.value, 0), 1) }
}
