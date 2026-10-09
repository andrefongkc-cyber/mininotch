import AppKit
import SwiftUI

/// The large lock screen player: the cover on its own, a card under it with the title, scrubber
/// and controls, and the synced lyrics beside or under both, scrolling and fading out at the top
/// and bottom. A glow or the blurred cover can go behind (off by default). Drawn after Canopy's
/// lock screen player, at the user's request.
///
/// Settings > Media > Lock Screen chooses the layout (`LockScreenMediaLayout`), whether the
/// player (cover and controls) and the lyrics each show, and the background and its strength. `Under the Notch` is not drawn
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
            VStack(spacing: LockScreenPlayerMetrics.stackedGap) {
                if showsPlayer { LockScreenPlayerColumn(track: track, metrics: metrics) }
                if showsLyrics {
                    LockScreenLyricsColumn(
                        track: track,
                        alignment: .center,
                        height: showsPlayer ? metrics.stackedLyricsHeight : metrics.columnHeight,
                        anchor: showsPlayer ? 0.3 : 0.42
                    )
                    .frame(width: metrics.lyricsWidth)
                }
            }
        case .playerRight:
            HStack(spacing: LockScreenPlayerMetrics.sideGap) {
                if showsLyrics {
                    LockScreenLyricsColumn(track: track, alignment: showsPlayer ? .trailing : .center, height: metrics.columnHeight)
                }
                if showsPlayer { LockScreenPlayerColumn(track: track, metrics: metrics) }
            }
        case .playerLeft, .underNotch:
            HStack(spacing: LockScreenPlayerMetrics.sideGap) {
                if showsPlayer { LockScreenPlayerColumn(track: track, metrics: metrics) }
                if showsLyrics {
                    LockScreenLyricsColumn(track: track, alignment: showsPlayer ? .leading : .center, height: metrics.columnHeight)
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
    /// The cover's side, which is also the controls card's width. A fifth of the screen's
    /// height, so the player scales with the display and still clears the clock and the
    /// password field on a 13-inch one.
    let artworkSide: CGFloat
    let lyricsWidth: CGFloat

    /// Room around the content for the background's blur to fade out in.
    static let backgroundSpill: CGFloat = 60
    /// Between the cover and the controls card under it.
    static let artworkGap: CGFloat = 12
    /// The controls card: title, artist, scrubber, times and the three buttons.
    static let controlsHeight: CGFloat = 132
    static let sideGap: CGFloat = 48
    static let stackedGap: CGFloat = 20

    init(screen: NSScreen, layout: LockScreenMediaLayout) {
        self.layout = layout
        let side = min(max(screen.frame.height * 0.2, 170), 240)
        artworkSide = layout == .stacked ? (side * 0.85).rounded() : side.rounded()
        lyricsWidth = min(max(screen.frame.width * 0.32, 340), 520).rounded()
    }

    var columnHeight: CGFloat { artworkSide + Self.artworkGap + Self.controlsHeight }
    /// The line being sung and about one either side of it.
    var stackedLyricsHeight: CGFloat { 140 }

    var windowSize: CGSize {
        let spill = Self.backgroundSpill * 2
        switch layout {
        case .stacked:
            return CGSize(
                width: max(artworkSide, lyricsWidth) + spill,
                height: columnHeight + Self.stackedGap + stackedLyricsHeight + spill
            )
        case .playerLeft, .playerRight, .underNotch:
            return CGSize(width: artworkSide + Self.sideGap + lyricsWidth + spill, height: columnHeight + spill)
        }
    }
}

/// The cover on its own, and under it a separate card with the song, the scrubber and previous,
/// play and next.
private struct LockScreenPlayerColumn: View {
    let track: NowPlayingTrack
    let metrics: LockScreenPlayerMetrics

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var controller: NowPlayingController { environment.nowPlaying }

    var body: some View {
        VStack(spacing: LockScreenPlayerMetrics.artworkGap) {
            artwork
            controls
        }
        .frame(width: metrics.artworkSide)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing \(track.title) by \(track.artist)")
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Group {
            if let image = controller.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                shape
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: metrics.artworkSide * 0.3))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }
        }
        .frame(width: metrics.artworkSide, height: metrics.artworkSide)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(track.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(track.artist.isEmpty ? track.sourceAppName : track.artist)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .padding(.bottom, 8)

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let elapsed = controller.elapsed(at: context.date)
                VStack(spacing: 2) {
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
                control("backward.fill", label: "Previous", size: 17, .previousTrack)
                Spacer(minLength: 0)
                control(track.isPlaying ? "pause.fill" : "play.fill", label: track.isPlaying ? "Pause" : "Play", size: 22, .playPause)
                Spacer(minLength: 0)
                control("forward.fill", label: "Next", size: 17, .nextTrack)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: metrics.artworkSide, height: LockScreenPlayerMetrics.controlsHeight)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                shape.fill(Color.black.opacity(0.38))
                if settings.media.tintFromArtwork {
                    shape.fill(controller.palette.primary.opacity(0.2))
                }
                shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
    }

    private func control(_ symbol: String, label: String, size: CGFloat, _ command: MediaCommand) -> some View {
        Button {
            controller.send(command)
        } label: {
            TransportSymbol.image(symbol, pointSize: size, weight: .semibold)
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The lyrics, with the line being sung large and bright at a fixed height and the rest dimmed,
/// sliding up as the song goes and fading out towards the top and bottom edges, with no box
/// around them. Clicking a line plays from it, when the player can seek.
///
/// Without synced lyrics, it shows the song's title and artist large instead, so the column is
/// never an empty space or an error on someone's lock screen.
private struct LockScreenLyricsColumn: View {
    let track: NowPlayingTrack
    let alignment: HorizontalAlignment
    let height: CGFloat
    /// How far down the column the line being sung sits, as a fraction of its height.
    var anchor: CGFloat = 0.42

    @Environment(AppEnvironment.self) private var environment
    /// Where each laid-out line's top sits in the list, measured, since lines wrap to different
    /// heights. The list is slid by the current line's entry.
    @State private var lineTops: [UUID: CGFloat] = [:]

    private var controller: NowPlayingController { environment.nowPlaying }

    /// Lines either side of the current one that are laid out at all. Enough to fill the column
    /// at any anchor; anything further away is past the fade anyway.
    private static let reach = 8

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

    private var scaleAnchor: UnitPoint {
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
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: anchor * 0.75),
                        .init(color: .black, location: anchor + 0.2),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            songTitle
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: frameAlignment)
        }
    }

    /// Every line near the current one, in one column slid so the current line's top sits at
    /// `anchor`. Before the first line is sung, the first line takes that place.
    private func lines(_ lyrics: Lyrics, current: Int?) -> some View {
        let focus = current ?? 0
        let start = max(focus - Self.reach, 0)
        let end = min(focus + Self.reach + 1, lyrics.lines.count)
        let shown = start < end ? Array(lyrics.lines[start..<end].enumerated()) : []
        let focusTop = lyrics.lines.indices.contains(focus) ? lineTops[lyrics.lines[focus].id] ?? 0 : 0

        return VStack(alignment: alignment, spacing: 14) {
            ForEach(shown, id: \.element.id) { offset, line in
                let index = start + offset
                lyricLine(line, isCurrent: index == current, isPast: current.map { index < $0 } ?? false)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named(Self.listSpace)).minY
                    } action: { top in
                        lineTops[line.id] = top
                    }
            }
        }
        .coordinateSpace(.named(Self.listSpace))
        .offset(y: height * anchor - focusTop)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .top)
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: focusTop)
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: current)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lyrics")
    }

    private static let listSpace = "lockScreenLyrics"

    private func lyricLine(_ line: LyricLine, isCurrent: Bool, isPast: Bool) -> some View {
        Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white.opacity(isCurrent ? 1 : isPast ? 0.3 : 0.45))
            .multilineTextAlignment(textAlignment)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            // Scaled rather than set in a smaller font, so a line growing into the current one
            // animates instead of jumping, and every line takes the same room.
            .scaleEffect(isCurrent ? 1 : 0.84, anchor: scaleAnchor)
            .contentShape(Rectangle())
            .onTapGesture {
                guard controller.canSeek, let timestamp = line.timestamp else { return }
                controller.seek(toLyricsTime: timestamp)
            }
    }

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
