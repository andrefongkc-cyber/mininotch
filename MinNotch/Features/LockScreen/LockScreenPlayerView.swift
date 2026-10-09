import AppKit
import SwiftUI

/// The large lock screen player: a card with the cover, title, scrubber and controls, the synced
/// lyrics beside or under it, and a glow or the blurred cover behind both. Drawn after Canopy's
/// lock screen player, at the user's request.
///
/// Settings > Media > Lock Screen chooses the layout (`LockScreenMediaLayout`), whether the card
/// and the lyrics each show, and the background and its strength. `Under the Notch` is not drawn
/// here: that is the strip `LockScreenView` draws under the notch.
///
/// It sits over the wallpaper, not on the notch, so it draws in white the way the lock screen's
/// own clock does, whatever the Notch Style. The window is placed between the clock and the
/// password field (`windowFrame(on:layout:)`), and the background fades out well inside it, so
/// no edge of the window ever shows.
struct LockScreenPlayerView: View {
    let metrics: LockScreenPlayerMetrics
    /// Told whenever a song appears or goes, so the window takes clicks only while there is
    /// something to press.
    var onInteractiveChange: (Bool) -> Void = { _ in }

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var controller: NowPlayingController { environment.nowPlaying }
    private var media: MediaSettings { settings.media }
    private var showsPlayer: Bool { media.lockScreenShowsPlayer || !media.lockScreenShowsLyrics }
    private var showsLyrics: Bool { media.lockScreenShowsLyrics }

    /// Where the window goes on `screen`, in screen coordinates: centred, a little below the
    /// middle, which is clear of the lock screen clock above and the password field below.
    static func windowFrame(on screen: NSScreen, layout: LockScreenMediaLayout) -> CGRect {
        let metrics = LockScreenPlayerMetrics(screen: screen, layout: layout)
        let size = metrics.windowSize
        let frame = screen.frame
        let centreFromTop = frame.height * 0.56
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - centreFromTop - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    var body: some View {
        ZStack {
            if let track = controller.track {
                background
                content(track)
                    .padding(LockScreenPlayerMetrics.backgroundSpill)
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.windowSize.width, height: metrics.windowSize.height)
        .environment(\.notchStyle, environment.notchStyle().darkVariant)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.35), value: controller.track?.artworkKey)
        .onChange(of: controller.track != nil, initial: true) { _, interactive in
            onInteractiveChange(interactive)
        }
    }

    @ViewBuilder
    private func content(_ track: NowPlayingTrack) -> some View {
        switch metrics.layout {
        case .stacked:
            VStack(spacing: 18) {
                if showsPlayer { LockScreenPlayerCard(track: track, metrics: metrics) }
                if showsLyrics {
                    LockScreenLyricsColumn(
                        track: track,
                        alignment: .center,
                        visibleLines: showsPlayer ? 2 : 6,
                        height: showsPlayer ? LockScreenPlayerMetrics.lyricLineHeight * 2 : metrics.cardHeight
                    )
                }
            }
        case .playerRight:
            HStack(spacing: 40) {
                if showsLyrics {
                    LockScreenLyricsColumn(track: track, alignment: showsPlayer ? .trailing : .center, visibleLines: 6, height: metrics.cardHeight)
                }
                if showsPlayer { LockScreenPlayerCard(track: track, metrics: metrics) }
            }
        case .playerLeft, .underNotch:
            HStack(spacing: 40) {
                if showsPlayer { LockScreenPlayerCard(track: track, metrics: metrics) }
                if showsLyrics {
                    LockScreenLyricsColumn(track: track, alignment: showsPlayer ? .leading : .center, visibleLines: 6, height: metrics.cardHeight)
                }
            }
        }
    }

    /// A soft wash behind the player, inset by the spill so its blur reaches nothing before
    /// the window's edge does.
    @ViewBuilder
    private var background: some View {
        let strength = media.lockScreenBackgroundStrength
        let inset = LockScreenPlayerMetrics.backgroundSpill
        let blur = inset * 0.7
        switch media.lockScreenBackground {
        case .none:
            EmptyView()
        case .glow:
            let palette = controller.palette
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [palette.glowPrimary, palette.glowSecondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(inset)
                .blur(radius: blur)
                .opacity(0.55 * strength)
                .allowsHitTesting(false)
        case .artwork:
            if let image = controller.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: metrics.windowSize.width - inset * 2,
                        height: metrics.windowSize.height - inset * 2
                    )
                    .clipShape(Ellipse())
                    .saturation(1.4)
                    .blur(radius: blur)
                    .opacity(0.8 * strength)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Sizes for the player, worked out once from the screen, so the window and the view agree.
struct LockScreenPlayerMetrics {
    let layout: LockScreenMediaLayout
    /// The cover's side. A fifth of the screen's height, so the player scales with the display
    /// and still clears the clock and the password field on a 13-inch one.
    let artworkSide: CGFloat
    let lyricsWidth: CGFloat

    /// Room around the content for the background's blur to fade out in.
    static let backgroundSpill: CGFloat = 60
    static let cardPadding: CGFloat = 16
    /// Title, artist, scrubber, times and controls under the cover.
    static let cardInfoHeight: CGFloat = 140
    static let lyricLineHeight: CGFloat = 44

    init(screen: NSScreen, layout: LockScreenMediaLayout) {
        self.layout = layout
        let side = min(max(screen.frame.height * 0.2, 150), 240)
        artworkSide = layout == .stacked ? (side * 0.8).rounded() : side.rounded()
        lyricsWidth = min(max(screen.frame.width * 0.32, 340), 520).rounded()
    }

    var cardWidth: CGFloat { artworkSide + Self.cardPadding * 2 }
    var cardHeight: CGFloat { artworkSide + Self.cardInfoHeight + Self.cardPadding * 2 }

    var windowSize: CGSize {
        let spill = Self.backgroundSpill * 2
        switch layout {
        case .stacked:
            return CGSize(
                width: max(cardWidth, lyricsWidth) + spill,
                height: cardHeight + 18 + Self.lyricLineHeight * 2 + spill
            )
        case .playerLeft, .playerRight, .underNotch:
            return CGSize(width: cardWidth + 40 + lyricsWidth + spill, height: cardHeight + spill)
        }
    }
}

/// The cover, the song, the scrubber and previous, play and next, on a dark tinted card.
private struct LockScreenPlayerCard: View {
    let track: NowPlayingTrack
    let metrics: LockScreenPlayerMetrics

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var controller: NowPlayingController { environment.nowPlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .padding(.bottom, 14)

            Text(track.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(track.artist.isEmpty ? track.sourceAppName : track.artist)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .padding(.bottom, 12)

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let elapsed = controller.elapsed(at: context.date)
                VStack(spacing: 3) {
                    MediaScrubber(
                        progress: track.hasDuration ? elapsed / track.duration : 0,
                        tint: .white,
                        isSeekable: controller.canSeek && track.hasDuration,
                        onScrubStateChange: { controller.isScrubbing = $0 },
                        onCommit: { controller.seek(to: $0 * track.duration) }
                    )
                    if settings.media.showTimecodes {
                        HStack {
                            Text(TimeFormat.string(from: elapsed))
                            Spacer(minLength: 0)
                            Text("-" + TimeFormat.string(from: max(track.duration - elapsed, 0)))
                        }
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                control("backward.fill", label: "Previous", size: 18, .previousTrack)
                Spacer(minLength: 0)
                control(track.isPlaying ? "pause.fill" : "play.fill", label: track.isPlaying ? "Pause" : "Play", size: 24, .playPause)
                Spacer(minLength: 0)
                control("forward.fill", label: "Next", size: 18, .nextTrack)
                Spacer(minLength: 0)
            }
        }
        .padding(LockScreenPlayerMetrics.cardPadding)
        .frame(width: metrics.cardWidth, height: metrics.cardHeight)
        .background {
            let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
            ZStack {
                shape.fill(Color.black.opacity(0.42))
                if settings.media.tintFromArtwork {
                    shape.fill(controller.palette.primary.opacity(0.22))
                }
                shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing \(track.title) by \(track.artist)")
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if let image = controller.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: metrics.artworkSide, height: metrics.artworkSide)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        } else {
            shape
                .fill(Color.white.opacity(0.08))
                .frame(width: metrics.artworkSide, height: metrics.artworkSide)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: metrics.artworkSide * 0.3))
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }

    private func control(_ symbol: String, label: String, size: CGFloat, _ command: MediaCommand) -> some View {
        Button {
            controller.send(command)
        } label: {
            TransportSymbol.image(symbol, pointSize: size, weight: .semibold)
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The lyrics, a few lines at a time, with the line being sung large and bright and the rest
/// dimmed, moving up as the song goes. Clicking a line plays from it, when the player can seek.
///
/// Without synced lyrics, it shows the song's title and artist large instead, so the column is
/// never an empty space or an error on someone's lock screen.
private struct LockScreenLyricsColumn: View {
    let track: NowPlayingTrack
    let alignment: HorizontalAlignment
    let visibleLines: Int
    let height: CGFloat

    @Environment(AppEnvironment.self) private var environment

    private var controller: NowPlayingController { environment.nowPlaying }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    var body: some View {
        if let lyrics = controller.lyrics, lyrics.isSynced {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                lines(lyrics, current: lyrics.index(at: controller.lyricsTime(at: context.date)))
            }
            // From the top, so the line being sung stays put and a long line pushes the
            // later ones down and out, where they fade rather than being cut.
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: Alignment(horizontal: alignment, vertical: .top))
            .clipped()
            .mask {
                LinearGradient(
                    stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            songTitle
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: frameAlignment)
        }
    }

    /// Two lines before the current one, the current one, and the ones after it, so the line
    /// being sung sits about a third of the way down. The stacked layout shows two: the current
    /// line and the next.
    private func lines(_ lyrics: Lyrics, current: Int?) -> some View {
        let before = visibleLines > 2 ? 2 : 0
        let start = max((current ?? -1) - before, 0)
        let end = min(start + visibleLines, lyrics.lines.count)
        let shown = start < end ? Array(lyrics.lines[start..<end].enumerated()) : []
        // Early in a song there are fewer lines before the current one than there is room for;
        // the gap is left empty, so the line being sung (or, before the first, the first to be
        // sung) is always at the same height and the block does not jump when it fills.
        let missing = before - ((current ?? -1) - start)

        return VStack(alignment: alignment, spacing: 10) {
            ForEach(shown, id: \.element.id) { offset, line in
                let index = start + offset
                let isCurrent = index == current
                Text(line.text.isEmpty ? "♪" : line.text)
                    .font(.system(size: isCurrent ? 26 : 21, weight: .bold))
                    .foregroundStyle(.white.opacity(isCurrent ? 1 : (current.map { index < $0 } ?? false) ? 0.25 : 0.4))
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard controller.canSeek, let timestamp = line.timestamp else { return }
                        controller.seek(toLyricsTime: timestamp)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .padding(.top, CGFloat(max(missing, 0)) * Self.lineSlot)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: current)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lyrics")
    }

    /// A dimmed line's height and the spacing after it.
    private static let lineSlot: CGFloat = 36

    private var songTitle: some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(track.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Text(track.artist.isEmpty ? track.sourceAppName : track.artist)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .multilineTextAlignment(textAlignment)
        .lineLimit(2)
    }
}
