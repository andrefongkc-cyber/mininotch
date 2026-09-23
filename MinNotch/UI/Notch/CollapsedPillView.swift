import SwiftUI

/// What the closed pill has to show, and how wide that makes it.
///
/// Sizing lives here rather than in the view so `NotchRootView` can set the surface width
/// from exactly the same numbers the view lays out with. When those two disagree, content
/// spills past the shape and gets cut off by the transparent area around it.
struct CollapsedPillContent: Equatable {
    var artwork: NSImage?
    var activity: LiveActivity?
    var isPlaying: Bool
    var battery: BatteryStatus
    var showPercentage: Bool
    /// When false the pill stays exactly the size of the hardware notch and shows nothing,
    /// which on a notched display makes it invisible.
    var isExtended: Bool
    /// The user's arrangement. Which indicators appear, and which side each is on, comes
    /// from here rather than from a fixed assignment in the view.
    var leadingLayout: [PillIndicator]
    var trailingLayout: [PillIndicator]

    /// Distance from the pill's outer edge to its content.
    ///
    /// `NotchShape` insets its body by the shoulder radius, so the outermost points of the
    /// pill are the concave fillets, not solid fill. Content has to clear them or it is
    /// drawn over transparency and reads as a clipped, glitchy edge.
    static let contentInset = Metrics.notchShoulderRadius + 6

    /// Spacing between the pieces of a flank. Named because the width calculation and the
    /// layout both read them, and a discrepancy of a few points shows up as content clipped
    /// against the shape's shoulder.
    static let itemSpacing: CGFloat = 5
    static let detailSpacing: CGFloat = 3
    static let glyphWidth: CGFloat = 16
    static let batteryGlyphWidth: CGFloat = 22

    // MARK: What is showing

    /// The indicators assigned to one side that currently have something to say.
    ///
    /// Assignment and availability are separate questions. A user can place the battery on
    /// the leading side and it still will not draw on a Mac with no battery, and that is not
    /// the layout being wrong.
    func items(on side: PillSide) -> [PillIndicator] {
        guard isExtended else { return [] }
        let assigned = side == .leading ? leadingLayout : trailingLayout
        return assigned.filter { hasContent($0) }
    }

    enum PillSide { case leading, trailing }

    /// True when this indicator has something to draw right now.
    private func hasContent(_ indicator: PillIndicator) -> Bool {
        switch indicator {
        case .artwork: return artwork != nil
        case .activity: return activity != nil
        case .playing:
            // The waveform stands in for a cover, so it steps aside whenever one is actually
            // being drawn. Placing both is allowed and means "show it when there is no art".
            return isPlaying && artwork == nil
        case .battery: return battery.isPresent
        }
    }

    /// Trailing text for a running activity, e.g. a countdown.
    ///
    /// A glyph alone is no use for a timer: knowing one is running is not the thing you
    /// wanted, the number of minutes left is.
    var activityDetail: String? {
        guard let detail = activity?.detail, !detail.isEmpty else { return nil }
        return detail
    }

    var hasLeading: Bool { !items(on: .leading).isEmpty }
    var hasTrailing: Bool { !items(on: .trailing).isEmpty }

    // MARK: Sizing

    /// Width of one indicator's own content.
    private func width(of indicator: PillIndicator) -> CGFloat {
        switch indicator {
        case .artwork:
            return Metrics.pillArtworkSize
        case .activity:
            let detail = activityDetail.map { Self.detailSpacing + Self.measure($0) } ?? 0
            return Self.glyphWidth + detail
        case .playing:
            return Self.glyphWidth
        case .battery:
            // Measured at the widest the label ever gets, not at the current value. The
            // digits are monospaced, so sizing to "68" would still make the pill a character
            // narrower than at "100" and it would visibly resize as the battery drained.
            let label = showPercentage ? Self.detailSpacing + Self.measure("100") : 0
            return Self.batteryGlyphWidth + label
        }
    }

    /// Room one side's content needs, inset included.
    ///
    /// Summed from whatever the user assigned, in the same order and with the same spacing
    /// the view lays out. Nothing here knows which indicator is "the wide one": that used to
    /// be baked in, and it stopped being true the moment either side could hold anything.
    private func contentWidth(on side: PillSide) -> CGFloat {
        let showing = items(on: side)
        guard !showing.isEmpty else { return 0 }

        let content = showing.reduce(CGFloat(0)) { $0 + width(of: $1) }
        let gaps = Self.itemSpacing * CGFloat(showing.count - 1)
        return content + gaps + Self.contentInset
    }

    /// Width of each flank. Both sides get the same, even when only one has anything in it.
    ///
    /// The surface is centred on the display, so the dead zone in the middle only sits over
    /// the camera housing while the flanks match. Widen one side alone and the whole pill
    /// shifts by half that amount, sliding the cutout off the hardware it exists to hide
    /// behind.
    var flankWidth: CGFloat {
        max(contentWidth(on: .leading), contentWidth(on: .trailing))
    }

    func width(for geometry: NotchGeometry) -> CGFloat {
        geometry.collapsedSize.width + flankWidth * 2
    }

    /// Width of `text` in the font the pill actually draws it in.
    static func measure(_ text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }
}

/// The closed state.
///
/// At rest the pill is exactly the size of the hardware notch, so on a notched Mac it sits
/// entirely behind the camera housing and the top of the screen looks untouched. Turning on
/// the indicators in Settings > Layout widens it either side of the cutout, which is the
/// only place content on that hardware is actually visible. A display with no physical notch
/// is always extended, because it has nothing to hide behind.
struct CollapsedPillView: View {
    let geometry: NotchGeometry
    let content: CollapsedPillContent

    var body: some View {
        // Padding first, then the fixed width. The other order adds the inset *outside* a
        // frame that already contained it, so the row came out `contentInset` wider than
        // the pill on each side and the overflow was centred, pushing content out past the
        // edge onto transparency.
        HStack(spacing: 0) {
            flank(.leading)
                .padding(.leading, CollapsedPillContent.contentInset)
                .frame(width: content.flankWidth, alignment: .leading)

            // The dead zone under the camera housing. Never a drop target and never drawn
            // in: it is a `Spacer` rather than a colour precisely so clicks in it fall
            // through to whatever is behind the window.
            Spacer(minLength: 0)
                .frame(width: geometry.collapsedSize.width)

            flank(.trailing)
                .padding(.trailing, CollapsedPillContent.contentInset)
                .frame(width: content.flankWidth, alignment: .trailing)
        }
        .frame(
            width: content.width(for: geometry),
            height: geometry.collapsedSize.height
        )
        .animation(Motion.content, value: content.hasLeading)
        .animation(Motion.content, value: content.hasTrailing)
    }

    // MARK: Sides

    /// Draws whatever the user assigned to one side, in their order.
    ///
    /// Guarded on the side being empty rather than only on its width: a view in a zero-width
    /// frame is not clipped by SwiftUI, so an unguarded thumbnail spills outside the pill.
    @ViewBuilder
    private func flank(_ side: CollapsedPillContent.PillSide) -> some View {
        let showing = content.items(on: side)

        if showing.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: CollapsedPillContent.itemSpacing) {
                ForEach(showing) { indicator in
                    view(for: indicator)
                }
            }
            // Never let the row compress: a squeezed SF Symbol is what makes a glyph look
            // chopped off rather than simply smaller, and a squeezed timecode becomes an
            // ellipsis.
            .fixedSize()
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func view(for indicator: PillIndicator) -> some View {
        switch indicator {
        case .artwork:
            if let artwork = content.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Metrics.pillArtworkSize, height: Metrics.pillArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
            }

        case .activity:
            if let activity = content.activity {
                HStack(spacing: CollapsedPillContent.detailSpacing) {
                    Image(systemName: activity.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(activity.tint)
                        .frame(width: CollapsedPillContent.glyphWidth)

                    if let detail = content.activityDetail {
                        Text(detail)
                            .font(Typography.timecode)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }

        case .playing:
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: CollapsedPillContent.glyphWidth)

        case .battery:
            HStack(spacing: CollapsedPillContent.detailSpacing) {
                if content.showPercentage {
                    Text("\(content.battery.percentage)")
                        .font(Typography.timecode)
                        .foregroundStyle(.white.opacity(0.92))
                }
                Image(systemName: content.battery.symbolName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(
                        content.battery.isCharging
                            ? Color(nsColor: .systemGreen)
                            : (content.battery.percentage <= 10
                                ? Color(nsColor: .systemRed)
                                : .white.opacity(0.92))
                    )
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: CollapsedPillContent.batteryGlyphWidth)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Battery \(content.battery.percentage) percent")
        }
    }
}
