import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Shelf widget: files parked on the notch, waiting to go somewhere else.
struct ShelfView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var service: ShelfService { environment.shelf }

    @State private var isAirDropTargeted = false

    static let preferredHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 8) {
            if service.items.isEmpty {
                HStack(spacing: 10) {
                    emptyState
                    airDropTile
                }
            } else {
                itemRow
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: dropTarget) { providers in
            accept(providers)
        }
    }

    private var dropTarget: Binding<Bool> {
        Binding(
            get: { service.isDropTargeted },
            set: { service.isDropTargeted = $0 }
        )
    }

    // MARK: Contents

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: service.isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 24))
                .foregroundStyle(
                    service.isDropTargeted
                        ? settings.appearance.resolvedAccent
                        : .white.opacity(0.35)
                )

            Text(service.isDropTargeted ? "Drop to hold" : "Shelf")
                .font(Typography.bodyEmphasised)
                .foregroundStyle(.white.opacity(0.75))

            Text("Drag files here to hold them, then drag them out wherever you need.")
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    service.isDropTargeted
                        ? settings.appearance.resolvedAccent
                        : Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: service.isDropTargeted ? 1.5 : 1, dash: [4, 4])
                )
        )
        .animation(Motion.hover, value: service.isDropTargeted)
    }

    private var itemRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(service.items) { item in
                    chip(item)
                }
                airDropTile
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    service.isDropTargeted ? settings.appearance.resolvedAccent : .clear,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
        )
        .animation(Motion.hover, value: service.isDropTargeted)
    }

    private func chip(_ item: ShelfItem) -> some View {
        let isSelected = service.selection.contains(item.id)
        let accent = settings.appearance.resolvedAccent

        return VStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 40, height: 40)

            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? accent.opacity(0.22) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent, lineWidth: 1.5)
                .opacity(isSelected ? 1 : 0)
        )
        // The drag source sits on top and takes the mouse, which is why clicks, removal and
        // AirDrop all come through it rather than through views underneath it.
        .overlay(
            ShelfDragSource(
                item: item,
                operationMask: operationMask,
                urlsToDrag: { service.items(startingFrom: item).map(\.url) },
                onClick: { modifiers in
                    let gesture: ShelfService.SelectionGesture = modifiers.contains(.command)
                        ? .toggle
                        : modifiers.contains(.shift) ? .range : .only
                    service.select(item, gesture)
                },
                onFinished: { operation, urls in
                    let dragged = service.items.filter { urls.contains($0.url) }
                    if operation.contains(.move) {
                        service.remove(dragged)
                    } else {
                        service.handleDragCompleted(dragged)
                    }
                },
                onAirDrop: { AirDropSender.shared.send(service.items(startingFrom: item).map(\.url)) },
                onRemove: { service.remove(service.items(startingFrom: item)) }
            )
        )
        .animation(Motion.hover, value: isSelected)
    }

    /// Sends the selection, or everything, with AirDrop when clicked, and sends whatever is
    /// dropped on it straight away, without keeping it on the shelf.
    ///
    /// Its own drop target, inside the shelf's. SwiftUI hands a drop to the innermost target
    /// under the pointer, so files dropped here go to AirDrop and files dropped anywhere else
    /// on the shelf are held.
    @ViewBuilder
    private var airDropTile: some View {
        if AirDropSender.shared.isAvailable {
            let accent = settings.appearance.resolvedAccent
            let targeted = isAirDropTargeted
            let toSend = service.itemsToSend.map(\.url)

            VStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(targeted ? accent : .white.opacity(toSend.isEmpty ? 0.35 : 0.8))
                    .frame(width: 40, height: 40)

                Text(service.selection.isEmpty ? "AirDrop" : "AirDrop \(service.selection.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .frame(width: 64)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(targeted ? accent.opacity(0.22) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(targeted ? accent : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !toSend.isEmpty else { return }
                AirDropSender.shared.send(toSend)
            }
            .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
                loadURLs(from: providers) { AirDropSender.shared.send($0) }
                return true
            }
            .help(toSend.isEmpty
                  ? "Drop files here to send them with AirDrop"
                  : service.selection.isEmpty
                      ? "Send everything on the shelf with AirDrop, or drop files here to send them"
                      : "Send the selected files with AirDrop, or drop files here to send them")
            .animation(Motion.hover, value: targeted)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))

            Spacer()

            Button("Clear") { service.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: 14)
    }

    private var footerText: String {
        let count = "\(service.items.count) of \(settings.shelf.maxItems)"
        guard !service.selection.isEmpty else { return count + " · Click to select, ⌘ or ⇧ for more" }
        return count + " · \(service.selection.count) selected"
    }

    /// What the drag advertises to the destination.
    ///
    /// This is the setting doing real work: advertising `.move` is what makes Finder move
    /// the original file rather than copy it. `.ask` advertises both and lets the modifier
    /// keys decide, which is the standard macOS behaviour.
    private var operationMask: NSDragOperation {
        switch settings.shelf.dropBehavior {
        case .copy: return .copy
        case .move: return .move
        case .ask: return [.copy, .move]
        }
    }

    private func accept(_ providers: [NSItemProvider]) -> Bool {
        loadURLs(from: providers) { urls in
            service.add(urls)
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        }
        return true
    }

    /// Loads every file URL a drop carries, then hands them over together, on main.
    private func loadURLs(from providers: [NSItemProvider], then deliver: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        // Each provider loads on a queue of its own, possibly at the same time as the others,
        // so the list they add to is behind a lock. It was a plain array, which several
        // loaders appending at once could corrupt.
        let collected = CollectedURLs()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                let urls = collected.all
                guard !urls.isEmpty else { return }
                deliver(urls)
            }
        }
    }
}

/// Makes a shelf chip draggable out to other apps.
///
/// SwiftUI's `.onDrag` cannot express the drag operation or report how the drag ended, and
/// both matter here: the operation is what tells Finder to move rather than copy, and the
/// result is what tells the shelf whether it is still holding the file.
struct ShelfDragSource: NSViewRepresentable {
    var item: ShelfItem
    var operationMask: NSDragOperation
    /// What a drag from this chip carries: the selection when this chip is in it.
    var urlsToDrag: () -> [URL]
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onFinished: (NSDragOperation, [URL]) -> Void
    var onAirDrop: () -> Void
    var onRemove: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        configure(view)
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        configure(view)
    }

    private func configure(_ view: DragView) {
        view.urlsToDrag = urlsToDrag
        view.mask = operationMask
        view.onClick = onClick
        view.onFinished = onFinished
        view.onAirDrop = onAirDrop
        view.onRemove = onRemove
        view.toolTip = item.url.path
    }

    final class DragView: NSView, NSDraggingSource {
        var urlsToDrag: (() -> [URL])?
        var mask: NSDragOperation = .copy
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onFinished: ((NSDragOperation, [URL]) -> Void)?
        var onAirDrop: (() -> Void)?
        var onRemove: (() -> Void)?

        /// Set once a drag has begun, so the mouse coming up afterwards is not also a click.
        private var didDrag = false
        /// What the current drag carries, fixed when it starts: the selection could change
        /// while the drag is in flight, and the end of the drag must act on what was dragged.
        private var draggedURLs: [URL] = []

        /// The notch panel never becomes key, so without this the first click on a chip would
        /// only be spent making the window respond.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            didDrag = false
        }

        override func mouseUp(with event: NSEvent) {
            if !didDrag { onClick?(event.modifierFlags) }
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didDrag, let urls = urlsToDrag?(), !urls.isEmpty else { return }
            didDrag = true
            draggedURLs = urls

            // One dragging item per file, which is what makes Finder and Mail take them all.
            // Their icons are fanned a few points apart, so the pointer visibly carries several.
            let size = NSSize(width: 48, height: 48)
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = size
                let offset = CGFloat(min(index, 4)) * 6
                draggingItem.setDraggingFrame(
                    NSRect(
                        origin: NSPoint(x: bounds.midX - size.width / 2 + offset, y: bounds.midY - size.height / 2 - offset),
                        size: size
                    ),
                    contents: icon
                )
                return draggingItem
            }

            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            mask
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            didDrag = false
            // A drag that landed nowhere should not change anything.
            guard operation != [] else { return }
            onFinished?(operation, draggedURLs)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()

            let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)

            if AirDropSender.shared.isAvailable {
                let airDrop = NSMenuItem(title: "AirDrop…", action: #selector(airDrop), keyEquivalent: "")
                airDrop.target = self
                menu.addItem(airDrop)
            }

            menu.addItem(.separator())

            let remove = NSMenuItem(title: "Remove from Shelf", action: #selector(removeItem), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)

            return menu
        }

        @objc private func reveal() {
            guard let urls = urlsToDrag?(), !urls.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }

        @objc private func airDrop() {
            onAirDrop?()
        }

        @objc private func removeItem() {
            onRemove?()
        }
    }
}

/// URLs gathered from several item providers at once.
private final class CollectedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) { lock.withLock { urls.append(url) } }
    var all: [URL] { lock.withLock { urls } }
}
