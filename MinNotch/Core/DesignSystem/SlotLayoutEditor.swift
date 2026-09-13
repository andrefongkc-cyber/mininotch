import SwiftUI

/// Something that can be dragged between the zones of a `SlotLayoutEditor`.
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
    /// Everything the palette can offer, in the order it offers it.
    static var arrangeableCatalogue: [Self] { get }
}

extension LayoutArrangeable where Self: RawRepresentable, Self.RawValue == String, Self: CaseIterable {
    var layoutID: String { rawValue }
    static func arrangeable(layoutID: String) -> Self? { Self(rawValue: layoutID) }
    static var arrangeableCatalogue: [Self] { Array(allCases) }
}

/// Drag-to-arrange over one or more ordered zones, plus a palette of everything not in use.
///
/// One component, used three times: the media transport row, the two flanks of the closed
/// pill, and the open panel's top strip. They are the same problem each time, an ordered list
/// of chips the user rearranges, and three bespoke drag implementations would have been three
/// places for the same edge cases to be got wrong.
///
/// Two rules the callers depend on:
///
/// - **An item exists in at most one zone.** Dropping it somewhere removes it from wherever
///   it was, so a caller can treat the zones as a partition and never has to de-duplicate.
/// - **Dropping on a chip inserts before it; dropping on the zone appends.** That is what
///   makes reordering within a zone possible at all, since a zone-level drop alone can only
///   ever mean "put it at the end".
///
/// What it deliberately does not offer is a zone that is only a drop target with nothing
/// drawn in it. The notch's dead zone over the camera housing has to stay a click-through
/// gap with nothing in it at all, so it is not modelled here: callers leave it out.
struct SlotLayoutEditor<Item: LayoutArrangeable>: View {

    /// One ordered destination.
    struct Zone: Identifiable {
        let id: String
        var title: String
        var items: Binding<[Item]>
        /// Shown in place of chips when the zone is empty.
        var emptyHint: String

        init(id: String, title: String, items: Binding<[Item]>, emptyHint: String = "Nothing here") {
            self.id = id
            self.title = title
            self.items = items
            self.emptyHint = emptyHint
        }
    }

    var zones: [Zone]
    var paletteTitle: String = "Not Shown"
    var paletteHint: String = "Drag here to remove"
    /// Restricts what the palette offers, for a caller whose catalogue is context-dependent.
    var catalogue: [Item] = Item.arrangeableCatalogue

    @State private var targetedZone: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(zones) { zone in
                lane(
                    title: zone.title,
                    id: zone.id,
                    items: zone.items.wrappedValue,
                    emptyHint: zone.emptyHint,
                    onDropItem: { append($0, to: zone) },
                    chipDrop: { dropped, before in insert(dropped, into: zone, before: before) }
                )
            }

            lane(
                title: paletteTitle,
                id: Self.paletteID,
                items: unplaced,
                emptyHint: "Everything is in use",
                onDropItem: { removeEverywhere($0) },
                chipDrop: { dropped, _ in removeEverywhere(dropped) }
            )
        }
    }

    private static var paletteID: String { "__palette" }

    // MARK: Lanes

    private func lane(
        title: String,
        id: String,
        items: [Item],
        emptyHint: String,
        onDropItem: @escaping (Item) -> Void,
        chipDrop: @escaping (Item, Item) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Typography.helper)
                .foregroundStyle(Palette.secondaryText)

            HStack(spacing: 6) {
                if items.isEmpty {
                    Text(emptyHint)
                        .font(Typography.helper)
                        .foregroundStyle(Palette.tertiaryText)
                        .padding(.vertical, 4)
                } else {
                    ForEach(items) { item in
                        chip(item)
                            .draggable(item.layoutID)
                            .dropDestination(for: String.self) { payload, _ in
                                guard let dropped = decode(payload) else { return false }
                                guard dropped != item else { return true }
                                chipDrop(dropped, item)
                                return true
                            }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.paneBackground.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        targetedZone == id ? Palette.controlAccent : Palette.separator,
                        style: StrokeStyle(lineWidth: targetedZone == id ? 1.5 : 1, dash: [4, 3])
                    )
            )
            // The zone-level drop is what "move it to the end" means. A chip-level drop
            // above takes precedence when the pointer is actually over a chip.
            .dropDestination(for: String.self) { payload, _ in
                guard let dropped = decode(payload) else { return false }
                onDropItem(dropped)
                return true
            } isTargeted: { isTargeted in
                targetedZone = isTargeted ? id : (targetedZone == id ? nil : targetedZone)
            }
            .animation(Motion.hover, value: targetedZone)
        }
    }

    private func chip(_ item: Item) -> some View {
        HStack(spacing: 5) {
            Image(systemName: item.layoutSymbol)
                .font(.system(size: 10, weight: .medium))
            Text(item.layoutTitle)
                .font(Typography.helper)
        }
        .foregroundStyle(Palette.primaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Palette.cardBackground)
        )
        .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 0.5))
        .contentShape(Capsule())
        .help("Drag to move \(item.layoutTitle)")
    }

    // MARK: Mutation

    private func decode(_ payload: [String]) -> Item? {
        guard let id = payload.first else { return nil }
        return Item.arrangeable(layoutID: id)
    }

    /// Everything in the catalogue that is not currently placed.
    private var unplaced: [Item] {
        let placed = Set(zones.flatMap { $0.items.wrappedValue })
        return catalogue.filter { !placed.contains($0) }
    }

    private func append(_ item: Item, to zone: Zone) {
        removeEverywhere(item)
        zone.items.wrappedValue.append(item)
    }

    private func insert(_ item: Item, into zone: Zone, before anchor: Item) {
        removeEverywhere(item)
        // The anchor's index is read after the removal, not before: taking the item out of
        // this same zone shifts everything after it, and an index captured beforehand would
        // insert one place too far to the right.
        let index = zone.items.wrappedValue.firstIndex(of: anchor) ?? zone.items.wrappedValue.endIndex
        zone.items.wrappedValue.insert(item, at: index)
    }

    private func removeEverywhere(_ item: Item) {
        for zone in zones {
            zone.items.wrappedValue.removeAll { $0 == item }
        }
    }
}
