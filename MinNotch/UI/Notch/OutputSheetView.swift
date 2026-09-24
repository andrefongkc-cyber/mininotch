import SwiftUI

/// Where sound plays, and how loud, in place of the lyrics on the Now Playing card.
///
/// Opened from the output button beside the song's title. The same space the full lyrics list
/// uses, and never both at once, so the card has one fixed height per state. Everything here
/// writes the system's own settings through `AudioOutputService`: picking a row is picking it in
/// the Sound menu, and the bar is the system volume.
struct OutputSheetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private static let rowHeight: CGFloat = 24
    private static let volumeRowHeight: CGFloat = 20
    private static let spacing: CGFloat = 8

    /// As tall as the outputs there are, one to four, then it scrolls. Known before the sheet
    /// opens, because the output button reads the list first, so the card is the right height
    /// on its first frame rather than growing once the list arrives.
    static func height(deviceCount: Int) -> CGFloat {
        volumeRowHeight + spacing + listHeight(deviceCount)
    }

    /// Explicit, because a `ScrollView` has no height of its own and lays out at zero inside
    /// the panel.
    private static func listHeight(_ deviceCount: Int) -> CGFloat {
        rowHeight * CGFloat(min(max(deviceCount, 1), 4))
    }

    private var service: AudioOutputService { environment.audioOutputs }
    private var accent: Color { settings.appearance.resolvedAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            volumeRow

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(service.devices) { device in
                        row(device)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: Self.listHeight(service.devices.count))
        }
        .frame(height: Self.height(deviceCount: service.devices.count), alignment: .top)
        .onAppear { service.beginObserving() }
        .onDisappear {
            service.endObserving()
            // Closing the notch puts the list away, so it does not greet the next opening.
            environment.nowPlaying.isShowingOutputSheet = false
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            TransportSymbol.image(volumeSymbol, pointSize: 11, weight: .medium)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)

            if let volume = service.volume {
                MediaScrubber(
                    progress: service.isMuted ? 0 : volume,
                    tint: accent,
                    isSeekable: true,
                    onScrubStateChange: { _ in },
                    onCommit: { service.setVolume($0) },
                    onChange: { service.setVolume($0) }
                )
                .accessibilityLabel("Volume")
            } else {
                Text("This output's volume is set on the device itself.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                environment.nowPlaying.isShowingOutputSheet = false
            } label: {
                TransportSymbol.image("xmark", pointSize: 9, weight: .bold)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close the sound outputs")
            .accessibilityLabel("Close sound outputs")
        }
        .frame(height: Self.volumeRowHeight)
    }

    private var volumeSymbol: String {
        guard let volume = service.volume, !service.isMuted, volume > 0 else { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    private func row(_ device: AudioOutputDevice) -> some View {
        let isCurrent = device.id == service.defaultID

        return Button {
            service.select(device)
        } label: {
            HStack(spacing: 8) {
                TransportSymbol.image(device.symbolName, pointSize: 12, weight: .medium)
                    .foregroundStyle(isCurrent ? accent : Color.white.opacity(0.6))
                    .frame(width: 20)

                Text(device.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isCurrent {
                    TransportSymbol.image("checkmark", pointSize: 10, weight: .bold)
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCurrent ? "Sound is playing here" : "Play sound through \(device.name)")
    }
}
