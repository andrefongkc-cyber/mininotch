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
/// - **Dropping on an icon inserts before it; dropping on a side appends.** That is what makes
///   reordering possible at all, since a side-level drop alone can only mean "at the end".
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

    @State private var targeted: String?
    @State private var hovered: Item?

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
        let leadingCount = leading.wrappedValue.count
        let trailingCount = trailing?.wrappedValue.count ?? 0
        // Both flanks at the width of the fuller one, as on the real pill, which is what keeps
        // the cutout over the camera.
        let count = CGFloat(max(leadingCount, trailingCount, 1))
        let slot = CGSize(width: 26, height: 22)
        let flank = count * slot.width + (count - 1) * Self.gap + 8
        let total = min(flank * 2 + Self.cutoutWidth, stageWidth - 24)
        let fitted = (total - Self.cutoutWidth) / 2

        return HStack(spacing: 0) {
            side(.leading, slot: slot, width: fitted, alignment: .trailing)
            cutout(height: 28)
            side(.trailing, slot: slot, width: fitted, alignment: .leading)
        }
        .frame(height: 28)
        .padding(.horizontal, 6)
        .background(NotchShape(shoulderRadius: 6, bottomRadius: 10).fill(Color.black))
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

    private func side(_ side: Side, slot: CGSize, width: CGFloat?, alignment: Alignment) -> some View {
        let placed = items(of: side).wrappedValue
        let id = zoneID(side)

        return HStack(spacing: Self.gap) {
            if placed.isEmpty {
                placeholder(slot)
            } else {
                ForEach(placed) { item in
                    placedIcon(item, side: side, slot: slot)
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
        .frame(maxWidth: width == nil ? .infinity : nil)
        .contentShape(Rectangle())
        // A drop on the side, not on an icon, means "at the end". An icon's own drop takes
        // precedence when the pointer is actually over one.
        .modifier(DropTarget(id: id, targeted: $targeted) { payload in
            guard let dropped = decode(payload) else { return false }
            append(dropped, to: side)
            return true
        })
        .animation(Motion.hover, value: targeted)
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

    private func placedIcon(_ item: Item, side: Side, slot: CGSize) -> some View {
        let isHovered = hovered == item
        let size = isProminent(item) ? slot.height * 0.6 : min(13, slot.height * 0.52)

        return Image(systemName: item.layoutSymbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: slot.width, height: slot.height)
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
            .help(canRemove(item) ? item.layoutTitle : "\(item.layoutTitle): can be moved, not removed")
            .modifier(DragSource(payload: item.layoutID) { dragPreview(item) })
            .modifier(DropTarget(id: nil, targeted: $targeted) { payload in
                guard let dropped = decode(payload) else { return false }
                guard dropped != item else { return true }
                insert(dropped, into: side, before: item)
                return true
            })
    }

    private func dragPreview(_ item: Item) -> some View {
        Image(systemName: item.layoutSymbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 34, height: 30)
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

    private func insert(_ item: Item, into side: Side, before anchor: Item) {
        removeEverywhere(item)
        // The anchor's index is read after the removal, not before: taking the item out of
        // this same side shifts everything after it, and an index captured beforehand would
        // insert one place too far to the right.
        let target = items(of: side)
        let index = target.wrappedValue.firstIndex(of: anchor) ?? target.wrappedValue.endIndex
        target.wrappedValue.insert(item, at: index)
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
