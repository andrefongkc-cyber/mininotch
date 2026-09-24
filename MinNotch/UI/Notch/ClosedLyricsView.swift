import SwiftUI

/// The line being sung, under the closed pill, for as long as a song with synced lyrics plays.
///
/// Settings > Media > Lyrics > Show Lyrics When Closed. The same shape and size as the sneak
/// peek, so switching between the two on a track change is the strip's contents changing and
/// not the notch changing size. The pill's own indicators stay in the top band, as in the peek,
/// and nothing readable goes there: on notched hardware it is behind the camera housing.
///
/// The current line is highlighted word by word, as on the card, with the next line underneath.
/// Only synced lyrics are shown: an unsynced list has no idea which line is being sung, and a
/// strip that sat on the first line for the whole song would be worse than none.
struct ClosedLyricsView: View {
    let geometry: NotchGeometry
    let pillContent: CollapsedPillContent
    let lyrics: Lyrics

    @Environment(AppEnvironment.self) private var environment

    /// The sneak peek's size, deliberately. See the type's note.
    static func size(for geometry: NotchGeometry, pillWidth: CGFloat) -> CGSize {
        SneakPeekView.size(for: geometry, pillWidth: pillWidth)
    }

    /// Fast enough that the highlight lands on the word, as on the card's strip. It runs only
    /// while this is on screen, which is only while a song with synced lyrics is playing.
    private static let tick: TimeInterval = 0.1

    var body: some View {
        VStack(spacing: 0) {
            CollapsedPillView(geometry: geometry, content: pillContent)
                .frame(height: geometry.collapsedSize.height)

            TimelineView(.periodic(from: .now, by: Self.tick)) { context in
                let time = environment.nowPlaying.lyricsTime(at: context.date)
                let index = lyrics.index(at: time)

                VStack(spacing: 2) {
                    LyricsText.line(lyrics, at: index, time: time)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .animation(Motion.hover, value: index)

                    Text(nextLine(after: index))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            // Clear of the shoulder fillets, which are transparency rather than fill.
            .padding(.horizontal, CollapsedPillContent.contentInset + 6)
            .frame(height: SneakPeekView.bodyHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lyrics")
    }

    private func nextLine(after index: Int?) -> String {
        let next = (index ?? -1) + 1
        guard lyrics.lines.indices.contains(next) else { return "" }
        return lyrics.lines[next].text
    }
}
