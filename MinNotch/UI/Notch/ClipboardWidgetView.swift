import AppKit
import SwiftUI

/// The Clipboard widget: what you copied, offered back.
///
/// With Advanced > Clipboard > Blur Until Unlocked on, every row is blurred until an owner check
/// (`OwnerCheck`): the Unlock button, or a click on a row, which then copies it. The panel is held
/// open while the system's dialog is up, since entering a password takes the pointer elsewhere.
struct ClipboardWidgetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    let viewModel: NotchViewModel

    @State private var isChecking = false
    /// Why an unlock could not even be asked for, shown in place of the title for a moment.
    @State private var notice: String?

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
        .animation(Motion.content, value: service.isBlurred(in: settings))
        // Raises the poll rate while the list is visible. It records either way; see the
        // note on `ClipboardHistoryService`. The last one closing also blurs it again.
        .onAppear { service.beginSampling() }
        .onDisappear {
            service.endSampling()
            if isChecking { viewModel.isInteractionLocked = false }
        }
    }

    // MARK: Unlocking

    private func unlock(thenCopy item: ClipboardItem? = nil) {
        guard !isChecking else { return }
        isChecking = true
        viewModel.isInteractionLocked = true
        Task {
            let outcome = await OwnerCheck.confirm(reason: "show what you copied")
            isChecking = false
            viewModel.isInteractionLocked = false
            switch outcome {
            case .confirmed:
                service.reveal()
                if let item, service.isRevealed { service.copyToPasteboard(item) }
            case .declined:
                break
            case .unavailable(let reason):
                notice = "Can't unlock: \(reason)"
                try? await Task.sleep(for: .seconds(5))
                notice = nil
            }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            if let notice {
                Text(notice)
                    .font(Typography.helper)
                    .foregroundStyle(.orange.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("Clipboard")
                    .font(Typography.sectionHeader)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer(minLength: 0)

            if settings.advanced.clipboardBlurUntilUnlocked, !service.items.isEmpty {
                if service.isBlurred(in: settings) {
                    headerButton("Unlock", symbol: "lock.fill") { unlock() }
                        .help("Show what you copied, with Touch ID or your password")
                        .disabled(isChecking)
                } else {
                    headerButton("Hide", symbol: "eye.slash") { service.hide() }
                        .help("Blur the list again")
                }
            }

            if !service.items.isEmpty {
                Button("Clear") { service.clearAll() }
                    .buttonStyle(.plain)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Remove everything, pinned items included")
            }
        }
    }

    private func headerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .font(Typography.helper)
        .foregroundStyle(.white.opacity(0.7))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.3))
            Text("Nothing copied yet")
                .font(Typography.body)
                .foregroundStyle(.white.opacity(0.6))
            Text("Anything you copy shows up here. Passwords are skipped: from the Passwords app, and from any app that marks them private.")
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
        let isBlurred = service.isBlurred(in: settings)
        return ClipboardRow(
            item: item,
            accent: settings.appearance.resolvedAccent,
            isBlurred: isBlurred,
            onCopy: { isBlurred ? unlock(thenCopy: item) : service.copyToPasteboard(item) },
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
    /// Blur Until Unlocked, still locked. The kind of thing stays readable; what it says does not.
    let isBlurred: Bool
    let onCopy: () -> Void
    let onPin: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            icon

            if isBlurred {
                blurredPreview
            } else {
                Text(preview)
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

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
        .help(isBlurred ? "Click to unlock and copy back" : "Click to copy back")
        .accessibilityElement(children: .combine)
        // The label is read aloud and readable by any accessibility client, so it must not
        // carry what the blur hides.
        .accessibilityLabel(isBlurred ? "\(item.kind.rawValue), hidden" : "\(item.kind.rawValue): \(preview)")
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
                    .blur(radius: isBlurred ? 3 : 0, opaque: true)
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

    /// Enough that no letter of 12 point text survives, little enough that the row still reads
    /// as a line of text rather than a smudge.
    private static let blurRadius: CGFloat = 5

    /// Filler as long as the real text, blurred. The real text is never drawn while locked, so a
    /// blur that fails to apply, or anything that reads the view's text, finds only this.
    /// `drawingGroup` bakes the blur into the drawing rather than leaving it a layer filter, which
    /// a window capture does not draw, and the padding gives it room to fade out inside that layer.
    private var blurredPreview: some View {
        let filler = String(Self.filler.prefix(min(preview.count, Self.filler.count)))
        return Text(filler)
            .font(Typography.body)
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
            .padding(Self.blurRadius * 2)
            .blur(radius: Self.blurRadius)
            .drawingGroup()
            .padding(-Self.blurRadius * 2)
            .accessibilityHidden(true)
    }

    private static let filler = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor"

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
