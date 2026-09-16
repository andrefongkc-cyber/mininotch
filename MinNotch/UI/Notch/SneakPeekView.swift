import SwiftUI

/// What the closed notch shows for a moment when a new track starts.
///
/// A small drop below the pill rather than the whole panel. The first version of the peek
/// opened the full expanded panel for two seconds on every track change, which is a lot of
/// screen to take over for "the song changed", and it arrived with the tab strip, the
/// scrubber, and the transport, none of which anyone reaches for in two seconds.
///
/// The pill's own indicators stay where they are in the top band, so nothing jumps: the peek
/// only adds a strip of song information underneath. Nothing readable goes in the top band,
/// for the same reason as the panel: on notched hardware it is behind the camera housing.
struct SneakPeekView: View {
    let geometry: NotchGeometry
    let pillContent: CollapsedPillContent
    let track: NowPlayingTrack
    let artwork: NSImage?
    let palette: ArtworkPalette

    /// Height of the strip below the top band.
    static let bodyHeight: CGFloat = 46
    /// How much wider than the cutout the peek is, split between the two sides.
    static let extraWidth: CGFloat = 190
    static let cornerRadius: CGFloat = 16

    static func size(for geometry: NotchGeometry, pillWidth: CGFloat) -> CGSize {
        CGSize(
            width: max(pillWidth, geometry.collapsedSize.width + extraWidth),
            height: geometry.collapsedSize.height + bodyHeight
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            CollapsedPillView(geometry: geometry, content: pillContent)
                .frame(height: geometry.collapsedSize.height)

            HStack(spacing: 10) {
                artworkView

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track.artist.isEmpty ? track.sourceAppName : track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                PeekPlayingBars(palette: palette, isPlaying: track.isPlaying)
            }
            // Clear of the shoulder fillets, which are transparency rather than fill.
            .padding(.horizontal, CollapsedPillContent.contentInset + 6)
            .frame(height: Self.bodyHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing \(track.title) by \(track.artist)")
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                )
        }
    }
}

/// The small moving bars at the end of the peek, saying "this is playing" at a glance.
///
/// Moves to `VisualizerPulse`, the same pattern as the card's visualizer and the glow. Coloured from the cover through the lifted palette, which
/// reads on the peek's black ground whatever the sleeve looks like. The timeline pauses when
/// playback does, and the peek itself is only on screen for a couple of seconds.
struct PeekPlayingBars: View {
    let palette: ArtworkPalette
    let isPlaying: Bool

    static let barCount = 4
    static let barWidth: CGFloat = 3
    static let minimumHeight: CGFloat = 3
    static let maximumHeight: CGFloat = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.glowPrimary, palette.glowSecondary],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: Self.barWidth, height: height(index: index, at: time))
                }
            }
            .frame(width: CGFloat(Self.barCount) * (Self.barWidth + 2), height: Self.maximumHeight)
        }
        .accessibilityHidden(true)
    }

    /// The shared pulse runs slowly and stays within the middle half of its range, which suits
    /// the glow's long light but made four small bars look nearly still. The peek plays it faster
    /// and stretches that middle half to the full height.
    static let tempo = 2.4

    private func height(index: Int, at time: TimeInterval) -> CGFloat {
        guard isPlaying else { return Self.minimumHeight + 1 }
        let level = VisualizerPulse.level(index: index, at: time * Self.tempo, isPlaying: true)
        let stretched = min(max((level - 0.25) * 2, 0), 1)
        return Self.minimumHeight + (Self.maximumHeight - Self.minimumHeight) * CGFloat(stretched)
    }
}
