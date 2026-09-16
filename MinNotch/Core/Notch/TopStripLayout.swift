import CoreGraphics
import Foundation

/// Where each item of the open panel's top bar actually goes, given the room either side of
/// the cutout.
///
/// The user arranges two ordered lists in Settings, but the room either side of the cutout
/// depends on the panel width and the display's notch, and the number of tabs depends on which
/// features are on. Switching on one more feature used to push the last tab behind the camera
/// housing, where it could be neither seen nor clicked. So the arrangement is a preference and
/// this decides the placement:
///
/// - **Overflow crosses the cutout.** Whatever does not fit on the left moves to the start of
///   the right side, nearest the cutout, and the other way round. Both moves keep the order of
///   the two lists read end to end, so the bar still reads in the order the user chose.
/// - **Buttons get narrower before anything is lost.** Only if the items fit on neither side at
///   the full width are the buttons tightened, in steps.
/// - **The panel grows as a last resort.** `minimumPanelWidth` is how wide the panel must be
///   for everything to fit at the tightest width, and `NotchGeometry` never makes it narrower.
///
/// The widths here are the ones `ExpandedPanelView` lays out with, which is why both read them
/// from this type instead of each keeping its own.
struct TopStripLayout: Equatable {
    var leading: [TopStripItem]
    var trailing: [TopStripItem]
    /// Width of each icon button, tabs and settings alike.
    var buttonWidth: CGFloat

    static let itemSpacing: CGFloat = 4
    /// Tried in order; the first that fits wins.
    static let buttonWidths: [CGFloat] = [28, 24, 21]
    static let batteryIconWidth: CGFloat = 25
    static let batteryLabelSpacing: CGFloat = 4
    /// Gap kept between the items and the cutout, so nothing sits flush against the housing.
    static let cutoutClearance: CGFloat = 6
    /// Inset from the panel's outer edge, clear of the shoulder fillets.
    static var outerInset: CGFloat { Metrics.topStripPadding + Metrics.notchShoulderRadius }

    /// Room for items on one side of the cutout.
    static func flankCapacity(panelWidth: CGFloat, cutoutWidth: CGFloat) -> CGFloat {
        max(0, (panelWidth - cutoutWidth) / 2 - outerInset - cutoutClearance)
    }

    static func batteryWidth(showPercentage: Bool) -> CGFloat {
        guard showPercentage else { return batteryIconWidth }
        // The widest the label ever gets, so the bar does not reflow as the battery drains.
        return CollapsedPillContent.measure("100%") + batteryLabelSpacing + batteryIconWidth
    }

    // MARK: Resolving

    /// The two lists with anything that is not showing removed, each item once, any tab that is
    /// on neither side added to the end of the left, and any debug button that is on neither side
    /// added to the start of the right.
    ///
    /// A tab can be missing from both lists after a hand-edited settings file, or when a later
    /// version adds a tab the saved arrangement has never heard of. Either way a feature that is
    /// switched on must have a way in, so it joins the left, where every tab used to be. The debug
    /// buttons are never saved into an arrangement until someone drags one, so switching them on
    /// puts them beside the cutout on the right.
    static func resolve(
        leading: [TopStripItem],
        trailing: [TopStripItem],
        availableTabs: [NotchTab],
        showsBattery: Bool,
        showsDebug: Bool
    ) -> (leading: [TopStripItem], trailing: [TopStripItem]) {
        // A single tab has nothing to switch between, so the bar shows no tabs at all.
        let showsTabs = availableTabs.count > 1
        var seen = Set<TopStripItem>()

        func isShowing(_ item: TopStripItem) -> Bool {
            guard seen.insert(item).inserted else { return false }
            if let tab = item.tab { return showsTabs && availableTabs.contains(tab) }
            if item == .battery { return showsBattery }
            if item.isDebug { return showsDebug }
            return true
        }

        var left = leading.filter(isShowing)
        var right = trailing.filter(isShowing)

        if showsTabs {
            for tab in availableTabs where !seen.contains(TopStripItem(tab)) {
                left.append(TopStripItem(tab))
            }
        }
        if showsDebug {
            let missing = [TopStripItem.whatsNew, .tutorial].filter { !seen.contains($0) }
            right.insert(contentsOf: missing, at: 0)
        }
        return (left, right)
    }

    // MARK: Placing

    static func make(
        leading: [TopStripItem],
        trailing: [TopStripItem],
        availableTabs: [NotchTab],
        batteryWidth: CGFloat?,
        showsDebug: Bool,
        panelWidth: CGFloat,
        cutoutWidth: CGFloat
    ) -> TopStripLayout {
        let resolved = resolve(
            leading: leading,
            trailing: trailing,
            availableTabs: availableTabs,
            showsBattery: batteryWidth != nil,
            showsDebug: showsDebug
        )
        let capacity = flankCapacity(panelWidth: panelWidth, cutoutWidth: cutoutWidth)

        var fallback: TopStripLayout?
        for buttonWidth in buttonWidths {
            let widthOf: (TopStripItem) -> CGFloat = { $0 == .battery ? (batteryWidth ?? 0) : buttonWidth }
            let placed = place(resolved.leading, resolved.trailing, capacity: capacity, width: widthOf)
            let layout = TopStripLayout(leading: placed.left, trailing: placed.right, buttonWidth: buttonWidth)
            if placed.fits { return layout }
            fallback = layout
        }
        // Nothing fits even at the tightest width. `NotchGeometry` sizes the panel so this is
        // not reached on a real display; the panel's clip keeps it tidy if it ever is.
        return fallback ?? TopStripLayout(leading: resolved.leading, trailing: resolved.trailing, buttonWidth: buttonWidths[0])
    }

    /// Moves items across the cutout until both sides fit, or as close as they can get.
    ///
    /// First the left gives up its last items to the start of the right. Then, only if the right
    /// is still too full, it hands its first items back while the left has room. Every move
    /// shifts the split point in the two lists read end to end, so the order never changes, and
    /// the second pass ends on the longest left side that fits, which leaves the shortest right
    /// side possible: if any split fits, that one does.
    private static func place(
        _ leading: [TopStripItem],
        _ trailing: [TopStripItem],
        capacity: CGFloat,
        width: (TopStripItem) -> CGFloat
    ) -> (left: [TopStripItem], right: [TopStripItem], fits: Bool) {
        var left = leading
        var right = trailing

        while contentWidth(left, width) > capacity, let last = left.popLast() {
            right.insert(last, at: 0)
        }
        while contentWidth(right, width) > capacity, let first = right.first,
              contentWidth(left + [first], width) <= capacity {
            left.append(first)
            right.removeFirst()
        }

        let fits = contentWidth(left, width) <= capacity && contentWidth(right, width) <= capacity
        return (left, right, fits)
    }

    static func contentWidth(_ items: [TopStripItem], _ width: (TopStripItem) -> CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + width($1) } + itemSpacing * CGFloat(items.count - 1)
    }

    // MARK: Panel width

    /// The narrowest panel that fits every item at the tightest button width.
    ///
    /// Assumes the battery is showing whenever it is placed, because geometry is worked out from
    /// settings alone and a panel a little wider than needed costs nothing.
    static func minimumPanelWidth(
        leading: [TopStripItem],
        trailing: [TopStripItem],
        availableTabs: [NotchTab],
        showPercentage: Bool,
        showsDebug: Bool,
        cutoutWidth: CGFloat
    ) -> CGFloat {
        let resolved = resolve(
            leading: leading,
            trailing: trailing,
            availableTabs: availableTabs,
            showsBattery: true,
            showsDebug: showsDebug
        )
        let sequence = resolved.leading + resolved.trailing
        guard !sequence.isEmpty else { return 0 }

        let tightest = buttonWidths.last ?? 21
        let battery = batteryWidth(showPercentage: showPercentage)
        let widthOf: (TopStripItem) -> CGFloat = { $0 == .battery ? battery : tightest }

        // The best split of the whole sequence into a left and a right part.
        let widest = (0...sequence.count).map { split in
            max(
                contentWidth(Array(sequence[..<split]), widthOf),
                contentWidth(Array(sequence[split...]), widthOf)
            )
        }.min() ?? 0

        return cutoutWidth + 2 * (widest + outerInset + cutoutClearance)
    }
}
