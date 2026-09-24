import SwiftUI

/// Something that can be placed in an `IconLayoutEditor`.
///
/// The drag payload is a plain string rather than the value itself, because `Transferable`
/// on a settings enum would mean a codable representation and a uniform type identifier for
/// something that never leaves the process. The identifier is the enum's raw value, which is
/// already stable across builds because it is what gets persisted.
protocol LayoutArrangeable: Identifiable, Hashable {
    var layoutTitle: String { get }
    var layoutSymbol: String { get }
    /// Stable string carried as the drag payload.
    var layoutID: String { get }
    static func arrangeable(layoutID: String) -> Self?
}

extension LayoutArrangeable where Self: RawRepresentable, Self.RawValue == String {
    var layoutID: String { rawValue }
    static func arrangeable(layoutID: String) -> Self? { Self(rawValue: layoutID) }
}

/// Set by `--capture-layout`: `ImageRenderer` cannot draw a drag source or a drop target and
/// paints a placeholder over each, so a capture renders the editor without them.
@MainActor
enum LayoutEditorRendering {
    static var isStatic = false
}

/// Arranging what the notch shows, drawn as the notch itself.
///
/// The user sees a miniature of the surface being arranged, black on a wallpaper with the
/// camera housing where it really is, and a tray of icons underneath. Drag an icon into the
/// notch, or click it in the tray; drag one within the notch to reorder it or across the
/// cutout to change sides; drag it back to the tray, or hover and click its ×, to take it out.
/// This replaced lanes of text chips spread over three panes, which were correct and hard to
/// read: the thing being arranged is a picture, so the editor is one.
///
/// Rules the callers depend on, carried over from the chip editor:
///
/// - **An item exists in at most one side.** Dropping it anywhere removes it from wherever it
///   was, so a caller can treat the sides as a partition and never has to de-duplicate.
/// - **Where an icon lands is where it was let go.** Each side is one drop target, and the
///   drop goes between the icons either side of the pointer, judged by their midpoints, with a
///   marker there while the drag is over it. It used to be a target per icon that inserted
///   before it, plus a side that appended: anywhere off an icon meant "at the end", so on the
///   closed pill, whose left side hugs the cutout, dropping in the empty space on the left
///   moved an icon to the right, and moving one left needed a hit on a 26 point icon. Moving
///   right was easy and moving left was hard, which is how it was reported.
/// - **The cutout is not a destination.** On the real notch that band is a click-through gap
///   with nothing in it, so the miniature draws it and accepts nothing there.
///
/// The preview shows the user's arrangement, not the placement `TopStripLayout` resolves from
/// it. Showing an item somewhere other than where it was just dropped would make the editor
/// feel broken; the footer of the top bar card explains the overflow instead.
struct IconLayoutEditor<Item: LayoutArrangeable>: View {
    enum Surface {
        /// The closed pill: two flanks hugging the cutout, kept the same width.
        case closedPill
        /// The open panel's top strip: one group at each outer edge.
        case topBar
        /// A single centred row, the Now Playing transport controls.
        case controls
    }

    enum Side { case leading, trailing }

    var surface: Surface
    var leading: Binding<[Item]>
    /// Nil for a single row.
    var trailing: Binding<[Item]>?
    /// Everything that can be placed; the tray offers whatever of it is not placed.
    var catalogue: [Item]
    /// False for an item that may be moved but never taken out, such as a top bar tab, which
    /// would otherwise leave a feature that is switched on with no way to reach it.
    var canRemove: (Item) -> Bool = { _ in true }
    /// Where clicking an icon in the tray puts it. Nil means the emptier side.
    var sideForNewItem: ((Item) -> Side)?
    /// Drawn larger, as play and pause is on the real card.
    var isProminent: (Item) -> Bool = { _ in false }
    /// Fades the miniature while the surface is switched off, and says why.
    var inactiveCaption: String?
    /// Draws a placed item as the surface really shows it right now, instead of its symbol.
    /// Nil for an item with nothing to show at the moment, which then shows its symbol, faded.
    var livePreview: ((Item) -> AnyView?)? = nil

    @State private var targeted: String?
    @State private var hovered: Item?
    /// Where each placed icon is, in its side's own coordinate space, keyed by `frameKey`.
    @State private var iconFrames: [String: CGRect] = [:]
    /// Where a drop would land, while a drag is over a side.
    @State private var insertion: Insertion?

    private struct Insertion: Equatable {
        var side: Side
        var index: Int
    }

    private static var trayID: String { "__tray" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            stage
            tray
        }
    }

    // MARK: Stage

    /// The wallpaper and the notch on it.
    private var stage: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(red: 0.30, green: 0.40, blue: 0.70), Color(red: 0.62, green: 0.42, blue: 0.66)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // The menu bar the notch sits in.
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(height: 22)
                    .frame(maxWidth: .infinity)

                surfaceView(width: geometry.size.width)
                    .opacity(inactiveCaption == nil ? 1 : 0.45)

                if let inactiveCaption {
                    Text(inactiveCaption)
                        .font(Typography.helper)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(height: stageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.6), lineWidth: 0.5)
        )
    }

    private var stageHeight: CGFloat {
        switch surface {
        case .closedPill: return inactiveCaption == nil ? 64 : 80
        case .topBar: return 112
        case .controls: return 96
        }
    }

    @ViewBuilder
    private func surfaceView(width: CGFloat) -> some View {
        switch surface {
        case .closedPill: closedPill(stageWidth: width)
        case .topBar: topBar(stageWidth: width)
        case .controls: controlsRow(stageWidth: width)
        }
    }

    /// Width of the camera housing in the miniature, and the gap between icons.
    private static var cutoutWidth: CGFloat { 92 }
    private static var gap: CGFloat { 2 }

    private func closedPill(stageWidth: CGFloat) -> some View {
        let slot = CGSize(width: 26, height: 22)

        // Both flanks at the width of the fuller one, as on the real pill, which is what keeps
        // the cutout over the camera. Measured rather than counted, because a live preview is
        // as wide as what it shows: a song title is not one icon wide.
        return EqualFlanks {
            side(.leading, slot: slot, width: nil, alignment: .trailing)
            cutout(height: 28)
            side(.trailing, slot: slot, width: nil, alignment: .leading)
        }
        .frame(height: 28)
        .padding(.horizontal, 6)
        .background(NotchShape(shoulderRadius: 6, bottomRadius: 10).fill(Color.black))
        .frame(maxWidth: stageWidth - 24)
    }

    private func topBar(stageWidth: CGFloat) -> some View {
        let panelWidth = min(stageWidth - 24, 520)
        let inset: CGFloat = 12
        let flankWidth = (panelWidth - inset * 2 - Self.cutoutWidth) / 2
        let slot = slotSize(fitting: max(leading.wrappedValue.count, trailing?.wrappedValue.count ?? 0), in: flankWidth)

        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                side(.leading, slot: slot, width: flankWidth, alignment: .leading)
                cutout(height: 30)
                side(.trailing, slot: slot, width: flankWidth, alignment: .trailing)
            }
            .frame(height: 30)

            panelContentHint
        }
        .padding(.horizontal, inset)
        .frame(width: panelWidth, height: 96, alignment: .top)
        .background(NotchShape(shoulderRadius: 8, bottomRadius: 16).fill(Color.black))
    }

    private func controlsRow(stageWidth: CGFloat) -> some View {
        let cardWidth = min(stageWidth - 40, 320)
        return VStack(spacing: 10) {
            // A scrubber, so the row reads as the bottom of the Now Playing card.
            HStack(spacing: 6) {
                Capsule().fill(Color.white.opacity(0.7)).frame(width: cardWidth * 0.3, height: 3)
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 3)
            }
            side(.leading, slot: CGSize(width: 30, height: 30), width: nil, alignment: .center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: cardWidth)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black))
        .frame(maxHeight: .infinity)
    }

    /// Grey bars under the top strip, so the miniature reads as an open panel.
    private var panelContentHint: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 120, height: 6)
                Capsule().fill(Color.white.opacity(0.10)).frame(width: 80, height: 6)
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 3)
            }
        }
        .padding(.horizontal, 6)
        .allowsHitTesting(false)
    }

    /// Icons shrink before they overflow, as the real top bar does.
    private func slotSize(fitting count: Int, in width: CGFloat) -> CGSize {
        let count = CGFloat(max(count, 1))
        let available = (width - 6 - (count - 1) * Self.gap) / count
        let side = min(26, max(18, available))
        return CGSize(width: side, height: 24)
    }

    /// The camera housing. Drawn, but not a drop target.
    private func cutout(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous)
                .fill(Color(white: 0.1))
            Circle()
                .fill(Color(white: 0.22))
                .frame(width: 6, height: 6)
                .overlay(Circle().fill(Color(red: 0.2, green: 0.25, blue: 0.4)).frame(width: 2.5, height: 2.5))
                .padding(.top, 7)
        }
        .frame(width: Self.cutoutWidth, height: height)
        .help("The camera housing. Nothing is shown here, so clicks go through to the menu bar.")
    }

    // MARK: Sides

    private func items(of side: Side) -> Binding<[Item]> {
        side == .leading ? leading : (trailing ?? leading)
    }

    private func zoneID(_ side: Side) -> String { side == .leading ? "leading" : "trailing" }

    private func frameKey(_ side: Side, _ item: Item) -> String { zoneID(side) + "|" + item.layoutID }

    private func side(_ side: Side, slot: CGSize, width: CGFloat?, alignment: Alignment) -> some View {
        let placed = items(of: side).wrappedValue
        let id = zoneID(side)

        return HStack(spacing: Self.gap) {
            if placed.isEmpty {
                placeholder(slot)
            } else {
                ForEach(placed) { item in
                    placedIcon(item, side: side, slot: slot)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(id))
                        } action: { frame in
                            iconFrames[frameKey(side, item)] = frame
                        }
                }
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Palette.controlAccent.opacity(targeted == id ? 0.35 : 0))
        )
        .frame(width: width, alignment: alignment)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
        .contentShape(Rectangle())
        .coordinateSpace(.named(id))
        .overlay(alignment: .topLeading) { insertionMarker(on: side, slot: slot) }
        .modifier(ZoneDropTarget(
            onUpdate: { location in
                targeted = id
                insertion = Insertion(side: side, index: insertionIndex(on: side, at: location.x))
            },
            onExit: {
                if targeted == id { targeted = nil }
                if insertion?.side == side { insertion = nil }
            },
            onDrop: { payload, location in
                let index = insertionIndex(on: side, at: location.x)
                targeted = nil
                insertion = nil
                guard let dropped = Item.arrangeable(layoutID: payload) else { return }
                place(dropped, on: side, at: index)
            }
        ))
        .animation(Motion.hover, value: targeted)
        .animation(Motion.hover, value: insertion)
    }

    /// The gap a drop at `x` goes into: after every icon whose middle is left of it.
    private func insertionIndex(on side: Side, at x: CGFloat) -> Int {
        let placed = items(of: side).wrappedValue
        var index = 0
        for (position, item) in placed.enumerated() {
            if let frame = iconFrames[frameKey(side, item)], x > frame.midX { index = position + 1 }
        }
        return index
    }

    /// A bar in the gap a drop would go into.
    @ViewBuilder
    private func insertionMarker(on side: Side, slot: CGSize) -> some View {
        let placed = items(of: side).wrappedValue
        let frames = placed.compactMap { iconFrames[frameKey(side, $0)] }
        if let insertion, insertion.side == side, !frames.isEmpty, frames.count == placed.count {
            let x: CGFloat = insertion.index == 0
                ? frames[0].minX - 1
                : insertion.index >= frames.count
                    ? frames[frames.count - 1].maxX + 1
                    : (frames[insertion.index - 1].maxX + frames[insertion.index].minX) / 2
            Capsule()
                .fill(Palette.controlAccent)
                .frame(width: 2.5, height: frames[0].height + 4)
                .offset(x: x - 1.25, y: frames[0].minY - 2)
                .allowsHitTesting(false)
        }
    }

    private func placeholder(_ slot: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            )
            .frame(width: slot.width, height: slot.height)
            .help("Drag an icon here")
    }

    /// An item as it sits on the surface: what it really shows, where there is a live preview,
    /// or its symbol.
    @ViewBuilder
    private func face(_ item: Item, slot: CGSize) -> some View {
        if let livePreview, let live = livePreview(item) {
            live
                .padding(.horizontal, 3)
                .frame(minWidth: slot.width, minHeight: slot.height)
        } else {
            let size = isProminent(item) ? slot.height * 0.6 : min(13, slot.height * 0.52)
            Image(systemName: item.layoutSymbol)
                .font(.system(size: size, weight: .medium))
                // Faded when the surface would show something here and has nothing right now,
                // so the miniature tells the truth without losing the handle to drag.
                .foregroundStyle(.white.opacity(livePreview == nil ? 0.92 : 0.4))
                .frame(width: slot.width, height: slot.height)
        }
    }

    private func placedIcon(_ item: Item, side: Side, slot: CGSize) -> some View {
        let isHovered = hovered == item
        let isIdle = livePreview != nil && livePreview?(item) == nil

        return face(item, slot: slot)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.18 : 0))
            )
            .overlay(alignment: .topTrailing) {
                if isHovered, canRemove(item) {
                    Button {
                        remove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, .white)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .help("Remove \(item.layoutTitle)")
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { hovered = item } else if hovered == item { hovered = nil }
            }
            .help(helpText(item, isIdle: isIdle))
            .modifier(DragSource(payload: item.layoutID) { dragPreview(item) })
    }

    private func helpText(_ item: Item, isIdle: Bool) -> String {
        let base = canRemove(item) ? item.layoutTitle : "\(item.layoutTitle): can be moved, not removed"
        return isIdle ? base + ". Nothing to show right now." : base
    }

    private func dragPreview(_ item: Item) -> some View {
        face(item, slot: CGSize(width: 34, height: 30))
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black))
    }

    // MARK: Tray

    private var tray: some View {
        let isTargeted = targeted == Self.trayID
        let hasRemovable = zonesItems.contains(where: canRemove)

        return VStack(alignment: .leading, spacing: 6) {
            WrappingRow(spacing: 8) {
                if unplaced.isEmpty {
                    Text(hasRemovable ? "Everything is shown. Drag an icon here to take it out." : "Everything is shown.")
                        .font(Typography.helper)
                        .foregroundStyle(Palette.tertiaryText)
                        .padding(.vertical, 18)
                } else {
                    ForEach(unplaced) { item in
                        trayIcon(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.paneBackground.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Palette.controlAccent : Palette.separator,
                        style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: [4, 3])
                    )
            )
            .modifier(DropTarget(id: Self.trayID, targeted: $targeted) { payload in
                guard let dropped = decode(payload), canRemove(dropped) else { return false }
                remove(dropped)
                return true
            })
            .animation(Motion.hover, value: targeted)
        }
    }

    private func trayIcon(_ item: Item) -> some View {
        VStack(spacing: 4) {
            Image(systemName: item.layoutSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 38, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black))
            Text(item.layoutTitle)
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 70)
        .contentShape(Rectangle())
        .onTapGesture { add(item) }
        .modifier(DragSource(payload: item.layoutID) { dragPreview(item) })
        .help("Click to add \(item.layoutTitle), or drag it into place")
    }

    // MARK: Mutation

    private var zonesItems: [Item] {
        leading.wrappedValue + (trailing?.wrappedValue ?? [])
    }

    /// Everything in the catalogue that is not currently placed.
    private var unplaced: [Item] {
        let placed = Set(zonesItems)
        return catalogue.filter { !placed.contains($0) }
    }

    private func decode(_ payload: [String]) -> Item? {
        guard let id = payload.first else { return nil }
        return Item.arrangeable(layoutID: id)
    }

    /// A click in the tray: onto the side the caller names, or the emptier one.
    private func add(_ item: Item) {
        guard let trailing else {
            append(item, to: .leading)
            return
        }
        let side = sideForNewItem?(item)
            ?? (trailing.wrappedValue.count < leading.wrappedValue.count ? .trailing : .leading)
        append(item, to: side)
    }

    private func append(_ item: Item, to side: Side) {
        removeEverywhere(item)
        items(of: side).wrappedValue.append(item)
    }

    /// Puts an item into the gap `index` names on a side, counted with the item still wherever
    /// it was. Taking it out of this same side first shifts every gap after it one to the left,
    /// so a gap past its old place is one less once it has gone.
    private func place(_ item: Item, on side: Side, at index: Int) {
        var index = index
        if let current = items(of: side).wrappedValue.firstIndex(of: item), current < index {
            index -= 1
        }
        removeEverywhere(item)
        let target = items(of: side)
        target.wrappedValue.insert(item, at: min(max(index, 0), target.wrappedValue.count))
    }

    /// Taking an item out, unless it is one that has to stay placed.
    private func remove(_ item: Item) {
        guard canRemove(item) else { return }
        if hovered == item { hovered = nil }
        removeEverywhere(item)
    }

    private func removeEverywhere(_ item: Item) {
        leading.wrappedValue.removeAll { $0 == item }
        trailing?.wrappedValue.removeAll { $0 == item }
    }
}

/// One side of the surface as a drop target, reporting where over it the drag is.
///
/// A `DropDelegate` rather than `dropDestination`, because only the delegate is told the
/// pointer's position while the drag moves, and the marker needs it before anything is let go.
private struct ZoneDropTarget: ViewModifier {
    var onUpdate: @MainActor (CGPoint) -> Void
    var onExit: @MainActor @Sendable () -> Void
    /// Sendable because the payload arrives on the item provider's own queue and is handed
    /// back to main from there.
    var onDrop: @MainActor @Sendable (String, CGPoint) -> Void

    func body(content: Content) -> some View {
        if LayoutEditorRendering.isStatic {
            content
        } else {
            content.onDrop(of: [.plainText], delegate: Delegate(onUpdate: onUpdate, onExit: onExit, onDrop: onDrop))
        }
    }

    private struct Delegate: DropDelegate {
        var onUpdate: @MainActor (CGPoint) -> Void
        var onExit: @MainActor @Sendable () -> Void
        var onDrop: @MainActor @Sendable (String, CGPoint) -> Void

        func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            onUpdate(info.location)
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) { onExit() }

        func performDrop(info: DropInfo) -> Bool {
            let location = info.location
            guard let provider = info.itemProviders(for: [.plainText]).first else {
                onExit()
                return false
            }
            let onDrop = onDrop
            let onExit = onExit
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                let payload = (object as? NSString).map { String($0) }
                DispatchQueue.main.async {
                    guard let payload else { onExit(); return }
                    onDrop(payload, location)
                }
            }
            return true
        }
    }
}

/// Three views in a row with the outer two at the same width: the wider of the two.
///
/// The closed pill's rule, which keeps the cutout centred. Each flank is offered that width,
/// so a flank with less in it still spans its whole side and can be dropped on anywhere.
private struct EqualFlanks: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let flank = flankWidth(subviews)
        let middle = subviews[1].sizeThatFits(.unspecified)
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: flank * 2 + middle.width, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let flank = flankWidth(subviews)
        let middle = subviews[1].sizeThatFits(.unspecified).width
        let side = ProposedViewSize(width: flank, height: bounds.height)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: side)
        subviews[1].place(
            at: CGPoint(x: bounds.minX + flank, y: bounds.minY),
            proposal: ProposedViewSize(width: middle, height: bounds.height)
        )
        subviews[2].place(at: CGPoint(x: bounds.minX + flank + middle, y: bounds.minY), proposal: side)
    }

    private func flankWidth(_ subviews: Subviews) -> CGFloat {
        max(subviews[0].sizeThatFits(.unspecified).width, subviews[2].sizeThatFits(.unspecified).width)
    }
}

/// A drop target for a layout ID. With an `id`, it also reports whether a drag is over it.
private struct DropTarget: ViewModifier {
    var id: String?
    @Binding var targeted: String?
    var perform: ([String]) -> Bool

    func body(content: Content) -> some View {
        if LayoutEditorRendering.isStatic {
            content
        } else if let id {
            content.dropDestination(for: String.self) { payload, _ in
                perform(payload)
            } isTargeted: { isTargeted in
                targeted = isTargeted ? id : (targeted == id ? nil : targeted)
            }
        } else {
            content.dropDestination(for: String.self) { payload, _ in perform(payload) }
        }
    }
}

/// Makes a view draggable as a layout ID, with a preview drawn like the notch.
private struct DragSource<Preview: View>: ViewModifier {
    var payload: String
    @ViewBuilder var preview: () -> Preview

    func body(content: Content) -> some View {
        if LayoutEditorRendering.isStatic {
            content
        } else {
            content.draggable(payload) { preview() }
        }
    }
}

/// Lays its children out left to right, starting a new line when the next one would not fit.
struct WrappingRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
