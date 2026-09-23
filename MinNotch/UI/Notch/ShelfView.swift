import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Shelf widget: files parked on the notch, waiting to go somewhere else.
struct ShelfView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var service: ShelfService { environment.shelf }

    static let preferredHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 8) {
            if service.items.isEmpty {
                emptyState
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
        VStack(spacing: 4) {
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
                .fill(Color.white.opacity(0.07))
        )
        // The drag source sits on top and takes the mouse, which is why removal lives in its
        // context menu rather than in a button that would be underneath it.
        .overlay(
            ShelfDragSource(
                item: item,
                operationMask: operationMask,
                onFinished: { operation in
                    if operation.contains(.move) {
                        service.remove(item)
                    } else {
                        service.handleDragCompleted(item)
                    }
                },
                onRemove: { service.remove(item) }
            )
        )
    }

    private var footer: some View {
        HStack {
            Text("\(service.items.count) of \(settings.shelf.maxItems)")
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
            let urls = collected.all
            guard !urls.isEmpty else { return }
            service.add(urls)
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        }
        return true
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
    var onFinished: (NSDragOperation) -> Void
    var onRemove: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.configure(item: item, mask: operationMask, onFinished: onFinished, onRemove: onRemove)
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.configure(item: item, mask: operationMask, onFinished: onFinished, onRemove: onRemove)
    }

    final class DragView: NSView, NSDraggingSource {
        private var url: URL?
        private var mask: NSDragOperation = .copy
        private var onFinished: ((NSDragOperation) -> Void)?
        private var onRemove: (() -> Void)?

        func configure(
            item: ShelfItem,
            mask: NSDragOperation,
            onFinished: @escaping (NSDragOperation) -> Void,
            onRemove: @escaping () -> Void
        ) {
            self.url = item.url
            self.mask = mask
            self.onFinished = onFinished
            self.onRemove = onRemove
            toolTip = item.url.path
        }

        override func mouseDragged(with event: NSEvent) {
            guard let url else { return }

            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(url.absoluteString, forType: .fileURL)

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            // Drag the file's own icon, so what the pointer carries looks like the file.
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = NSSize(width: 48, height: 48)
            icon.size = size
            draggingItem.setDraggingFrame(
                NSRect(origin: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), size: size),
                contents: icon
            )

            beginDraggingSession(with: [draggingItem], event: event, source: self)
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
            // A drag that landed nowhere should not change anything.
            guard operation != [] else { return }
            onFinished?(operation)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()

            let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)

            menu.addItem(.separator())

            let remove = NSMenuItem(title: "Remove from Shelf", action: #selector(removeItem), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)

            return menu
        }

        @objc private func reveal() {
            guard let url else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
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
