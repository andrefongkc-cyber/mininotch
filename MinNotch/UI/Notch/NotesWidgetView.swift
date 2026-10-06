import AppKit
import SwiftUI

/// The Notes tab: one scratchpad, typed straight into the notch.
///
/// Typing needs the panel to take the keyboard, which it can (`NotchPanel.canBecomeKey`), and the
/// panel must not close under someone mid-sentence, so focus holds it open the same way Calendar's
/// Quick Add does (`isInteractionLocked`). The text view takes the Notch Style's appearance rather
/// than the system's, or a light-mode caret would be black on a dark style's black.
struct NotesWidgetView: View {
    @Environment(\.notchStyle) private var theme
    @Environment(AppEnvironment.self) private var environment
    let viewModel: NotchViewModel

    @FocusState private var isFocused: Bool

    static let preferredHeight: CGFloat = 160
    private static let footerHeight: CGFloat = 14

    private var notes: NotesService { environment.notes }

    var body: some View {
        @Bindable var notes = notes

        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes.text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($isFocused)
                    .environment(\.colorScheme, theme.isDark ? .dark : .light)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)

                if notes.text.isEmpty {
                    Text("Jot something down…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink.opacity(0.35))
                        .padding(.leading, 11)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.ink.opacity(isFocused ? 0.1 : 0.06))
            )
            // Alongside the text view's own click, not instead of it, so the click still places
            // the cursor where it lands.
            .simultaneousGesture(TapGesture().onEnded { focus() })

            footer
        }
        .animation(Motion.hover, value: isFocused)
        .onChange(of: isFocused) { _, focused in
            viewModel.isInteractionLocked = focused
        }
        .onChange(of: notes.wantsFocus) { _, wants in
            if wants { focus() }
        }
        .onAppear {
            if notes.wantsFocus { focus() }
        }
        .onDisappear {
            viewModel.isInteractionLocked = false
            notes.saveNow()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(summary)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(theme.ink.opacity(0.4))

            Spacer(minLength: 0)

            if !notes.text.isEmpty {
                Button("Copy") { notes.copyAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.ink.opacity(0.7))
                    .help("Copy the whole note")
            }
        }
        .frame(height: Self.footerHeight)
    }

    private var summary: String {
        let words = notes.text.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return "Kept on this Mac, between opens" }
        return words == 1 ? "1 word" : "\(words) words"
    }

    /// The panel takes the keyboard without the app coming forward, but a text view in it only
    /// gets typing once the app is active, as Calendar's Quick Add found.
    private func focus() {
        NSApp.activate(ignoringOtherApps: true)
        isFocused = true
        notes.focusHandled()
    }
}
