import AppKit
import SwiftUI

/// The Clipboard widget: what you copied, offered back.
struct ClipboardWidgetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var service: ClipboardHistoryService { environment.clipboard }

    static let preferredHeight: CGFloat = 168
    /// A `ScrollView` has no ideal height and lays out at zero inside the panel unless it is
    /// given one. Same reason `CalendarWidgetView.eventListHeight` exists.
    private static let listHeight: CGFloat = 128

    var body: some View {
        VStack(spacing: 6) {
            header

            if service.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Raises the poll rate while the list is visible. It records either way; see the
        // note on `ClipboardHistoryService`.
        .onAppear { service.beginSampling() }
        .onDisappear { service.endSampling() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 6) {
            Text("Clipboard")
                .font(Typography.sectionHeader)
                .foregroundStyle(.white.opacity(0.8))

            Spacer(minLength: 0)

            if !service.items.isEmpty {
                Button("Clear") { service.clearAll() }
                    .buttonStyle(.plain)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Remove everything, pinned items included")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing copied yet")
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.6))
            Text("Anything you copy shows up here. Passwords marked private by their app are skipped.")
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(service.items) { item in
                    row(item)
                }
            }
        }
        .frame(height: Self.listHeight)
    }

    // MARK: Rows

    private func row(_ item: ClipboardItem) -> some View {
        ClipboardRow(
            item: item,
            accent: settings.appearance.resolvedAccent,
            onCopy: { service.copyToPasteboard(item) },
            onPin: { service.togglePin(item) }
        )
    }
}

/// One remembered item.
///
/// Its own view rather than a method, because the hover highlight needs state and a method
/// returning a view cannot hold any.
private struct ClipboardRow: View {
    let item: ClipboardItem
    let accent: Color
    let onCopy: () -> Void
    let onPin: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            icon

            Text(preview)
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if item.isPinned || isHovering {
                Button(action: onPin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(item.isPinned ? accent : .white.opacity(0.5))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin so it is not pushed out")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.10 : 0.05))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onCopy)
        .help("Click to copy back")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.rawValue): \(preview)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                glyph
            }
        case .color:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: item.color ?? .clear))
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        case .text, .url:
            glyph
        }
    }

    private var glyph: some View {
        Image(systemName: item.kind.symbolName)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: 18, height: 18)
    }

    /// One line, whitespace collapsed. A copied code block is mostly newlines, and rendering
    /// them turns every row into a different height.
    private var preview: String {
        guard item.kind != .image else { return "Image" }
        let collapsed = item.text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.isEmpty ? item.text : collapsed
    }
}
