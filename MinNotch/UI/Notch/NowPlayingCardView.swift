import SwiftUI

/// The Now Playing widget: artwork, metadata, scrubber, transport, and optional lyrics.
struct NowPlayingCardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var controller: NowPlayingController { environment.nowPlaying }

    /// Height this card needs, excluding the panel's own padding and top strip.
    ///
    /// The transport row now sits inside the text column beside the artwork rather than
    /// under both, so the card is exactly as tall as the artwork unless lyrics are showing.
    /// That is what makes the panel short and wide rather than tall and narrow.
    static func preferredHeight(showingLyrics: Bool) -> CGFloat {
        let artworkRow = Metrics.artworkSize
        let lyricStrip: CGFloat = 40
        let spacing: CGFloat = 8

        guard showingLyrics else { return artworkRow }
        return artworkRow + spacing + lyricStrip
    }

    var body: some View {
        if let track = controller.track {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 14) {
                    artwork
                    // Fixed to the artwork's height with the transport pinned to the bottom,
                    // so the two columns end level and the card has one predictable height.
                    VStack(alignment: .leading, spacing: 4) {
                        metadata(track)
                        scrubber(track)
                        Spacer(minLength: 0)
                        controls
                    }
                    .frame(height: Metrics.artworkSize)
                }
                if settings.media.showLyrics {
                    lyricStrip
                }
            }
        } else {
            emptyState
        }
    }

    /// Either the lyrics or the reason there are none. Never nothing: a strip that
    /// silently disappears is the same to the eye as a broken feature.
    @ViewBuilder
    private var lyricStrip: some View {
        if let lyrics = controller.lyrics, !lyrics.isEmpty {
            LyricsStripView(lyrics: lyrics)
        } else {
            HStack(spacing: 6) {
                Image(systemName: controller.lyricsStatus == .searching ? "ellipsis" : "quote.bubble")
                    .font(.system(size: 11))
                Text(controller.lyricsStatus.message ?? "No lyrics available.")
                    .font(Typography.helper)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white.opacity(0.42))
            .frame(height: 40, alignment: .top)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = controller.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(width: Metrics.artworkSize, height: Metrics.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomLeading) {
            if settings.media.showVisualizer {
                VisualizerView(
                    palette: controller.palette,
                    isPlaying: controller.track?.isPlaying ?? false,
                    customImagePath: settings.media.customVisualizerPath
                )
                .frame(height: 22)
                .padding(.horizontal, 6)
                .padding(.bottom, 5)
            }
        }
        .background(artworkGlow)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .animation(Motion.content, value: controller.artwork)
    }

    /// The album art placement of the ambient glow.
    ///
    /// Traces the artwork's own rounded square rather than the notch outline, and sits behind
    /// the artwork so the light appears to come out from under it.
    @ViewBuilder
    private var artworkGlow: some View {
        let glow = settings.appearance.ambientGlow

        if glow.isActive(isLowPower: environment.battery.status.isLowPowerMode),
           glow.placements.contains(.albumArt) {
            AmbientGlowView(
                pathBuilder: AmbientGlowGeometry.artworkPath(cornerRadius: 8),
                settings: glow,
                palette: controller.palette,
                isPlaying: controller.track?.isPlaying ?? false,
                audio: environment.audioAnalyzer.current == nil ? nil : environment.audioAnalyzer,
                outlineSize: CGSize(width: Metrics.artworkSize, height: Metrics.artworkSize)
            )
        }
    }

    private func metadata(_ track: NowPlayingTrack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(track.artist.isEmpty ? track.sourceAppName : track.artist)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Redraws twice a second inside a `TimelineView` so only the position updates, rather
    /// than invalidating the whole panel on a timer.
    private func scrubber(_ track: NowPlayingTrack) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = controller.elapsed(at: context.date)
            let progress = track.hasDuration ? min(max(elapsed / track.duration, 0), 1) : 0

            VStack(spacing: 3) {
                MediaScrubber(
                    progress: progress,
                    tint: scrubberTint,
                    isSeekable: controller.canSeek && track.hasDuration,
                    onScrubStateChange: { controller.isScrubbing = $0 },
                    onCommit: { fraction in
                        controller.seek(to: fraction * track.duration)
                    }
                )

                if settings.media.showTimecodes {
                    HStack {
                        Text(TimeFormat.string(from: elapsed))
                        Spacer()
                        Text("-" + TimeFormat.string(from: max(track.duration - elapsed, 0)))
                    }
                    .font(Typography.timecode)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private var scrubberTint: Color {
        switch settings.appearance.sliderColor {
        case .accent: return settings.appearance.resolvedAccent
        case .albumArt: return controller.palette.primary
        case .monochrome: return .white.opacity(0.85)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)
            ForEach(settings.media.controlOrder) { control in
                if controller.supports(control) {
                    transportButton(control)
                }
            }
            Spacer(minLength: 0)
        }
        // Overlaid rather than placed in the row, so adding it does not shift the transport
        // buttons off centre.
        .overlay(alignment: .trailing) { effectsButton }
    }

    /// Cycles the two visual effects through their four combinations.
    ///
    /// One button rather than two switches, because this lives on the card where space is
    /// scarce and the states are naturally ordered. Settings > Media still offers them
    /// separately, and both surfaces read and write the same two stored values.
    private var effectsButton: some View {
        let mode = settings.mediaEffectsMode

        return Button {
            // Read at click time rather than tracked continuously: the modifier-change
            // modifier that would do the latter needs macOS 15, and this app targets 14.
            if NSEvent.modifierFlags.contains(.option) {
                advanceGlowStyle()
            } else {
                settings.mediaEffectsMode = mode.next
            }
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        } label: {
            Image(systemName: mode.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    mode == .off
                        ? Color.white.opacity(0.35)
                        : settings.appearance.resolvedAccent
                )
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(mode == .off ? 0 : 0.12))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(for: mode))
        .accessibilityLabel(mode.title)
        .animation(Motion.hover, value: mode)
        // Style and placement live behind the same button rather than in more of them: the
        // panel has no room, and both are changed far less often than the effects are turned
        // on and off. Sections rather than bare dividers, because three unlabelled lists of
        // checkmarks in one menu is not readable.
        .contextMenu {
            Button("Next Style") { advanceGlowStyle() }
                .disabled(!mode.showsAmbient)

            Section("Style") {
                ForEach(AmbientGlowStyleKind.allCases) { style in
                    Button {
                        settings.appearance.ambientGlow.style = style
                        settings.appearance.ambientGlow.isEnabled = true
                    } label: {
                        if style == settings.appearance.ambientGlow.style {
                            Label(style.title, systemImage: "checkmark")
                        } else {
                            Text(style.title)
                        }
                    }
                }
            }

            Section("Show Glow On") {
                ForEach(AmbientGlowPlacement.allCases) { placement in
                    Button {
                        togglePlacement(placement)
                    } label: {
                        if settings.appearance.ambientGlow.placements.contains(placement) {
                            Label(placement.title, systemImage: "checkmark")
                        } else {
                            Text(placement.title)
                        }
                    }
                    .disabled(!mode.showsAmbient)
                }
            }
        }
    }

    /// Turns one placement on or off from the notch itself.
    ///
    /// This is the glow setting people actually want to change without opening Settings, and
    /// the reason is that the two placements are completely different propositions. The
    /// closed pill sits in the menu bar all day, so a glow there is ambient lighting you have
    /// not asked for; the open panel is something you deliberately reached for. Wanting light
    /// on the second and not the first is the common case, and it used to mean opening the
    /// Settings window to express it.
    ///
    /// Writes the same stored set as Settings > Appearance, so the two cannot disagree.
    private func togglePlacement(_ placement: AmbientGlowPlacement) {
        var placements = settings.appearance.ambientGlow.placements
        if placements.contains(placement) {
            placements.remove(placement)
        } else {
            placements.insert(placement)
        }
        settings.appearance.ambientGlow.placements = placements
    }

    private func helpText(for mode: MediaEffectsMode) -> String {
        let base = "\(mode.title) — click to change, option-click or right-click for glow style and placement"
        guard mode.showsAmbient else { return base }
        return "\(base)\nStyle: \(settings.appearance.ambientGlow.style.title)"
    }

    private func advanceGlowStyle() {
        let all = AmbientGlowStyleKind.allCases
        let current = settings.appearance.ambientGlow.style
        let index = all.firstIndex(of: current) ?? 0
        settings.appearance.ambientGlow.style = all[(index + 1) % all.count]
        settings.appearance.ambientGlow.isEnabled = true
    }

    private func transportButton(_ control: MediaControl) -> some View {
        let isPlayPause = control == .playPause
        let isPlaying = controller.track?.isPlaying ?? false

        return Button {
            switch control {
            case .playPause: controller.send(.playPause)
            case .next: controller.send(.nextTrack)
            case .previous: controller.send(.previousTrack)
            case .shuffle: controller.send(.toggleShuffle)
            case .repeatMode: controller.send(.cycleRepeat)
            case .favorite: controller.send(.toggleFavorite)
            }
        } label: {
            Image(systemName: symbolName(for: control, isPlaying: isPlaying))
                .font(.system(size: isPlayPause ? 24 : 17, weight: .medium))
                .foregroundStyle(.white.opacity(isPlayPause ? 1 : 0.8))
                .frame(width: isPlayPause ? 30 : 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(control.title)
    }

    private func symbolName(for control: MediaControl, isPlaying: Bool) -> String {
        switch control {
        case .playPause: return isPlaying ? "pause.fill" : "play.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        case .shuffle: return "shuffle"
        case .repeatMode: return "repeat"
        case .favorite: return "heart"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing Playing")
                .font(Typography.bodyEmphasised)
                .foregroundStyle(.white.opacity(0.75))
            Text(emptyStateHint)
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.artworkSize)
        .padding(.horizontal, 12)
    }

    private var emptyStateHint: String {
        if AppleScriptRunner.shared.isAuthorizationDenied {
            return "MinNotch needs permission to control Music and Spotify. Open Settings > Media."
        }
        return "Start playing something in Music, Spotify, or any app."
    }
}

/// Two lines of lyrics: the current one with the word being sung picked out, the next one
/// dimmed underneath.
///
/// Word highlighting is the point of the strip. A whole line lighting up at once tells you
/// where you are in the song; picking out the word tells you where you are in the line,
/// which is what makes it readable while glancing rather than reading.
struct LyricsStripView: View {
    let lyrics: Lyrics

    @Environment(AppEnvironment.self) private var environment

    /// Fast enough that the highlight lands on the beat. Only the strip redraws, and only
    /// while the panel is open with lyrics showing.
    private static let tick: TimeInterval = 0.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
            let elapsed = environment.nowPlaying.lyricsTime(at: context.date)
            let index = lyrics.index(at: elapsed)

            VStack(alignment: .leading, spacing: 3) {
                currentLine(at: index, time: elapsed)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(Motion.hover, value: index)

                Text(nextLineText(after: index))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Lyrics")
    }

    // MARK: Lines

    /// Builds the line as one concatenated `Text` rather than a stack of word views, so it
    /// wraps, truncates, and kerns exactly as ordinary text does.
    private func currentLine(at index: Int?, time: TimeInterval) -> Text {
        guard let index, lyrics.lines.indices.contains(index) else {
            return Text(lyrics.lines.first?.text ?? "").foregroundStyle(.white.opacity(0.85))
        }

        let line = lyrics.lines[index]
        guard !line.words.isEmpty else {
            return Text(line.text).foregroundStyle(.white.opacity(0.9))
        }

        var result = Text("")
        for (wordIndex, word) in line.words.enumerated() {
            if wordIndex > 0 { result = result + Text(" ") }
            result = result + styled(word, at: time)
        }
        return result
    }

    private func styled(_ word: LyricWord, at time: TimeInterval) -> Text {
        if word.isCurrent(at: time) {
            return Text(word.text)
                .foregroundStyle(.white)
                .fontWeight(.bold)
        }
        // Sung words stay legible so the line still reads as a sentence; upcoming ones
        // recede so the eye lands on the current word without hunting.
        let opacity = word.isSung(at: time) ? 0.85 : 0.38
        return Text(word.text).foregroundStyle(.white.opacity(opacity))
    }

    private func nextLineText(after index: Int?) -> String {
        let next = (index ?? 0) + 1
        guard lyrics.lines.indices.contains(next) else { return "" }
        return lyrics.lines[next].text
    }
}
