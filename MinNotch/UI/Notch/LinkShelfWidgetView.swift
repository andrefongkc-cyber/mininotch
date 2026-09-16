import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Links widget: web links parked on the notch.
///
/// Clicking a row opens the link in the default browser, which is what a shelf of bookmarks is
/// for; the copy button beside it puts the link back on the pasteboard. Links come in by
/// dragging a link or a text selection onto the panel, or with ⌘V or the Paste button.
struct LinkShelfWidgetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var service: LinkShelfService { environment.linkShelf }

    static let preferredHeight: CGFloat = 168
    /// A `ScrollView` has no ideal height and lays out at zero inside the panel without one.
    private static let listHeight: CGFloat = 128

    /// Set briefly after a paste or drop that found no link, so the attempt is not silent.
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 6) {
            header

            if service.items.isEmpty {
                dropZone
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The whole widget accepts a drop, not only the empty state, so adding a second link is
        // as easy as the first.
        .onDrop(of: [.url, .plainText], isTargeted: dropTargetBinding) { providers in
            accept(providers)
        }
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(get: { service.isDropTargeted }, set: { service.isDropTargeted = $0 })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Links")
                .font(Typography.sectionHeader)
                .foregroundStyle(.white.opacity(0.8))

            if let notice {
                Text(notice)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.45))
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            // Also bound to ⌘V, which works whenever the panel has keyboard focus.
            Button("Paste") { paste() }
                .buttonStyle(.plain)
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.7))
                .keyboardShortcut("v", modifiers: .command)
                .help("Add the link on the clipboard (⌘V)")

            if !service.items.isEmpty {
                Button("Clear") { service.clearAll() }
                    .buttonStyle(.plain)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Remove every link")
            }
        }
        .animation(Motion.hover, value: notice)
    }

    // MARK: Empty

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: service.isDropTargeted ? "link.badge.plus" : "link")
                .font(.system(size: 22))
                .foregroundStyle(service.isDropTargeted ? settings.appearance.resolvedAccent : .white.opacity(0.35))
            Text(service.isDropTargeted ? "Drop to keep it" : "Drop or paste a link")
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.7))
            Text("Drag a link or a selection of text here, or press ⌘V. Click a saved link to open it.")
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    service.isDropTargeted ? settings.appearance.resolvedAccent : Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: service.isDropTargeted ? 1.5 : 1, dash: [4, 4])
                )
        )
        .animation(Motion.hover, value: service.isDropTargeted)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(service.items) { item in
                    LinkRow(
                        item: item,
                        icon: service.icons[item.host],
                        onOpen: { service.open(item) },
                        onCopy: { service.copy(item) },
                        onRemove: { service.remove(item) }
                    )
                }
            }
        }
        .frame(height: Self.listHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(settings.appearance.resolvedAccent, lineWidth: 1.5)
                .opacity(service.isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
    }

    // MARK: Input

    private func paste() {
        let added = service.addFromPasteboard()
        if added == 0 { flash("No link on the clipboard") }
    }

    /// Takes URLs first, then plain text, which covers a link dragged from a browser's address
    /// bar, a link inside a page, and a selection of text that contains links.
    private func accept(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        if LinkShelfService.normalised(url) == nil {
                            flash("Only web links can be kept")
                        } else {
                            service.add(url)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    DispatchQueue.main.async {
                        if service.add(fromText: text) == 0 { flash("No link in that text") }
                    }
                }
            }
        }
        return handled
    }

    private func flash(_ message: String) {
        notice = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if notice == message { notice = nil }
        }
    }
}

/// One saved link.
private struct LinkRow: View {
    let item: LinkItem
    let icon: NSImage?
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 8) {
            iconView

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                Text(item.url.absoluteString)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button(action: copy) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(didCopy ? 0.9 : 0.55))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy link")

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(isHovering ? 0.6 : 0.3))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.10 : 0.05))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onOpen)
        .help("Open \(item.url.absoluteString)")
        .contextMenu {
            Button("Open in Browser", action: onOpen)
            Button("Copy Link", action: copy)
            Divider()
            Button("Remove", action: onRemove)
        }
        .animation(Motion.hover, value: didCopy)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayTitle), \(item.url.absoluteString)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 16, height: 16)
        }
    }

    private func copy() {
        onCopy()
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { didCopy = false }
    }
}
