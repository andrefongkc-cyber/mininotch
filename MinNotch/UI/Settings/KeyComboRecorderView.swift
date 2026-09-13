import AppKit
import SwiftUI

/// Click-to-record shortcut field.
///
/// While recording, a local event monitor swallows key presses so recording ⌘Q does not
/// quit the app. Escape cancels and Delete clears, which is the convention every other
/// shortcut recorder on the platform uses.
struct KeyComboRecorderView: View {
    @Binding var combo: KeyCombo?
    /// Called with a conflicting action's name when the recorded combo is already taken.
    var conflictCheck: (KeyCombo) -> String?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var conflict: String?
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Button(action: toggleRecording) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .frame(minWidth: 74)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(background)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isRecording ? Palette.controlAccent : Palette.separator,
                                    lineWidth: isRecording ? 1.5 : 0.5
                                )
                        )
                        .foregroundStyle(isRecording ? Palette.controlAccent : Palette.primaryText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }

                if combo != nil && !isRecording {
                    Button {
                        combo = nil
                        conflict = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Remove shortcut")
                }
            }

            if let conflict {
                Text("Already used by \(conflict)")
                    .font(Typography.helper)
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
        .onDisappear(perform: stopRecording)
        .animation(Motion.hover, value: isRecording)
    }

    private var label: String {
        if isRecording { return "Press keys…" }
        return combo?.displayString ?? "Record"
    }

    private var background: Color {
        if isRecording { return Palette.controlAccent.opacity(0.12) }
        return isHovering ? Palette.separator.opacity(0.35) : Palette.separator.opacity(0.18)
    }

    // MARK: Recording

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard monitor == nil else { return }
        conflict = nil
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            // Returning nil swallows the event so the shortcut is not also performed.
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        // Escape cancels, Delete clears, matching the platform convention.
        if event.keyCode == 53 { stopRecording(); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            combo = nil
            stopRecording()
            return
        }

        guard let recorded = KeyCombo(event: event) else {
            // A bare key would swallow ordinary typing everywhere, so it is rejected.
            conflict = "a shortcut needs at least one modifier key"
            return
        }

        if let existing = conflictCheck(recorded) {
            conflict = existing
            stopRecording()
            return
        }

        combo = recorded
        conflict = nil
        stopRecording()
    }
}
