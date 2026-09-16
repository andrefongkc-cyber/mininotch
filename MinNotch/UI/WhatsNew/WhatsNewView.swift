import SwiftUI

/// The release notes window: what was added, improved, and removed, and where to find each.
///
/// Drawn in plain colours, like the tutorial, so `--capture-whats-new` can read it back from a
/// real window.
struct WhatsNewView: View {
    let notes: ReleaseNotes
    var onClose: () -> Void

    static let size = CGSize(width: 520, height: 600)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                WhatsNewContent(notes: notes)
            }

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.paneBackground)
    }

    private var footer: some View {
        HStack {
            Spacer(minLength: 0)
            Button("Got It", action: onClose)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Palette.cardBackground
                .overlay(alignment: .top) { Divider().overlay(Palette.separator) }
        )
    }
}

/// Everything inside the scroll view, separate so `--capture-whats-new` can render it: an
/// AppKit capture of a window does not draw `ScrollView` content.
struct WhatsNewContent: View {
    let notes: ReleaseNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            section("New", notes.added)
            section("Improved", notes.improved)
            section("Removed", notes.removed)
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(width: WhatsNewView.size.width, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's New in MinNotch \(notes.version)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.primaryText)
            Text("Hover over the notch or click it to open it. Everything below is also in Settings, from the menu bar icon.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [ReleaseNote]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)

                ForEach(items) { note in
                    row(note)
                }
            }
        }
    }

    private func row(_ note: ReleaseNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: note.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.controlAccent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.controlAccent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(note.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.primaryText.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if let howTo = note.howTo {
                    Text(howTo)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

}
