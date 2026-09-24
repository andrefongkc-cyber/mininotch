import SwiftUI

/// The Now Playing widget: artwork, metadata, scrubber, transport, and optional lyrics.
struct NowPlayingCardView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var controller: NowPlayingController { environment.nowPlaying }

    /// Height this card needs, excluding the panel's own padding and top strip.
    ///
    /// In Classic the transport row sits inside the text column beside the artwork rather
    /// than under both, so the card is exactly as tall as the artwork unless lyrics are
    /// showing. That is what makes the panel short and wide rather than tall and narrow.
    static func preferredHeight(
        style: NowPlayingCardStyle = .classic,
        showingLyrics: Bool,
        showingUpNext: Bool = false,
        showingLyricsSheet: Bool = false,
        showingOutputSheet: Bool = false,
        outputDeviceCount: Int = 1
    ) -> CGFloat {
        var height = headerHeight(style)
        if showingUpNext { height += spacing + upNextRowHeight }
        if showingOutputSheet {
            height += spacing + OutputSheetView.height(deviceCount: outputDeviceCount)
        } else if showingLyricsSheet {
            height += spacing + LyricsSheetView.height
        } else if showingLyrics {
            height += spacing + lyricStripHeight
        }
        return height
    }

    /// The part above Up Next and the lyrics, per style.
    static func headerHeight(_ style: NowPlayingCardStyle) -> CGFloat {
        switch style {
        case .classic: return Metrics.artworkSize
        case .compact: return compactArtworkSize + spacing + scrubberRowHeight
        case .fullArtwork: return fullArtworkHeight
        }
    }

    private static let spacing: CGFloat = 8
    private static let lyricStripHeight: CGFloat = 40
    static let upNextRowHeight: CGFloat = 18
    private static let compactArtworkSize: CGFloat = 56
    private static let scrubberRowHeight: CGFloat = 14
    private static let fullArtworkHeight: CGFloat = 132

    var body: some View {
        if let track = controller.track {
            VStack(alignment: .leading, spacing: Self.spacing) {
                switch settings.media.cardStyle {
                case .classic: classicHeader(track)
                case .compact: compactHeader(track)
                case .fullArtwork: fullArtworkHeader(track)
                }
                if controller.showsUpNext {
                    upNextRow
                }
                if controller.showsOutputSheet {
                    OutputSheetView()
                } else if controller.showsLyricsSheet, let lyrics = controller.lyrics {
                    LyricsSheetView(lyrics: lyrics)
                } else if settings.media.showLyrics {
                    lyricStrip
                }
            }
        } else {
            emptyState
        }
    }

    /// The next track, and how many follow it, on one line. Or the reason it cannot say.
    ///
    /// One line because the card's height is fixed per state: a row that grew with the queue
    /// would resize the panel on every track change.
    @ViewBuilder
    private var upNextRow: some View {
        HStack(spacing: 6) {
            Text("UP NEXT")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))

            switch controller.upNext {
            case .loaded(let items):
                if let first = items.first {
                    Text(first.title)
                        .font(Typography.helper.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    if !first.artist.isEmpty {
                        Text(first.artist)
                            .font(Typography.helper)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    if items.count > 1 {
                        Text("then \(items.dropFirst().map(\.title).joined(separator: ", "))")
                            .font(Typography.helper)
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            case .unavailable(let reason):
                Text(reason)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            case .idle:
                Text("Reading the queue…")
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 0)
        }
        .frame(height: Self.upNextRowHeight)
        .accessibilityElement(children: .combine)
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

    // MARK: Styles

    /// Artwork beside the title, scrubber and controls, all as tall as the artwork.
    private func classicHeader(_ track: NowPlayingTrack) -> some View {
        HStack(alignment: .top, spacing: 14) {
            artwork(size: Metrics.artworkSize)
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
    }

    /// One row, small cover, title and controls, with the scrubber under the whole row. Half
    /// the height of Classic, for people who want the panel out of the way.
    private func compactHeader(_ track: NowPlayingTrack) -> some View {
        VStack(spacing: Self.spacing) {
            HStack(spacing: 10) {
                artwork(size: Self.compactArtworkSize)
                metadata(track)
                transportButtons(spacing: 8)
                trailingCluster
            }
            .frame(height: Self.compactArtworkSize)

            inlineScrubber(track)
                .frame(height: Self.scrubberRowHeight)
        }
    }

    /// The cover fills the card: a blurred, darkened copy behind everything, the cover itself
    /// large on the left. The copy is only ever a background, so the text on it takes its
    /// legibility from the dark wash, never from the cover's colours.
    private func fullArtworkHeader(_ track: NowPlayingTrack) -> some View {
        let height = Self.fullArtworkHeight
        let inset: CGFloat = 10
        let coverSize = height - inset * 2

        return HStack(alignment: .top, spacing: 14) {
            artwork(size: coverSize)
            VStack(alignment: .leading, spacing: 4) {
                metadata(track, titleSize: 17)
                scrubber(track)
                Spacer(minLength: 0)
                controls
            }
            .frame(height: coverSize)
        }
        .padding(inset)
        .frame(height: height)
        .background {
            // An overlay on a plain colour, not a ZStack: a filled image is larger than the
            // space it is offered, and as a ZStack child it would size the background to
            // itself and spread the blur over the rest of the panel.
            Color.black
                .overlay {
                    if let image = controller.artwork {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 28, opaque: true)
                            .scaleEffect(1.3)
                    }
                }
                .overlay(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        }
        .animation(Motion.content, value: controller.artwork)
    }

    // MARK: Pieces

    @ViewBuilder
    private func artwork(size: CGFloat) -> some View {
        let corner: CGFloat = size < 70 ? 6 : 8
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
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomLeading) {
            if settings.media.showVisualizer {
                ZStack(alignment: .bottomLeading) {
                    // A dark fade up from the bottom edge, so the bars always have a dark
                    // ground to stand out against, whether the cover is black, red, or white.
                    // Clipped to the artwork's corners, and clear by halfway up, so the cover
                    // still reads as itself.
                    if VisualizerView.drawsBars(customImagePath: settings.media.customVisualizerPath) {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.45),
                                .init(color: .black.opacity(0.35), location: 0.72),
                                .init(color: .black.opacity(0.62), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                        .allowsHitTesting(false)
                    }

                    VisualizerView(
                        palette: controller.palette,
                        isPlaying: controller.track?.isPlaying ?? false,
                        customImagePath: settings.media.customVisualizerPath,
                        audio: environment.audioAnalyzer.isRunning ? environment.audioAnalyzer : nil
                    )
                    .frame(height: size * 0.21)
                    .padding(.horizontal, size * 0.06)
                    .padding(.bottom, size * 0.05)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if settings.media.showSourceBadge, let icon = sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 0.2, height: size * 0.2)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .padding(size * 0.04)
                    .help(controller.track?.sourceAppName ?? "")
                    .accessibilityLabel("Playing in \(controller.track?.sourceAppName ?? "")")
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .animation(Motion.content, value: controller.artwork)
    }

    /// The playing app's icon, when the source knows which app that is.
    private var sourceIcon: NSImage? {
        controller.track?.sourceBundleIdentifier.flatMap(AppIconCache.icon(forBundleIdentifier:))
    }

    private func metadata(_ track: NowPlayingTrack, titleSize: CGFloat = 15) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(track.artist.isEmpty ? track.sourceAppName : track.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if settings.media.showOutputButton {
                outputButton
            }
        }
    }

    /// Opens the list of sound outputs, or closes it.
    ///
    /// Beside the title rather than with pop-out and effects: a third button there left the
    /// transport controls too little room in the 420 point floating window, while the title
    /// already truncates and gives up the space without complaint.
    private var outputButton: some View {
        let isOpen = controller.isShowingOutputSheet

        return Button {
            // Read first, so the sheet opens at the height its list needs.
            if !isOpen { environment.audioOutputs.refresh() }
            controller.isShowingOutputSheet.toggle()
        } label: {
            TransportSymbol.image("airplayaudio", pointSize: 12, weight: .medium)
                .foregroundStyle(isOpen ? settings.appearance.resolvedAccent : Color.white.opacity(0.45))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isOpen ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Close the sound outputs" : "Choose where sound plays, and the volume")
        .accessibilityLabel(isOpen ? "Close sound outputs" : "Sound outputs")
        .animation(Motion.hover, value: isOpen)
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

    /// The scrubber on one line with its timecodes either side, for Compact.
    private func inlineScrubber(_ track: NowPlayingTrack) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = controller.elapsed(at: context.date)
            let progress = track.hasDuration ? min(max(elapsed / track.duration, 0), 1) : 0

            HStack(spacing: 8) {
                if settings.media.showTimecodes {
                    Text(TimeFormat.string(from: elapsed))
                        .frame(minWidth: 30, alignment: .leading)
                }
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
                    Text("-" + TimeFormat.string(from: max(track.duration - elapsed, 0)))
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
            .font(Typography.timecode)
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var scrubberTint: Color {
        switch settings.appearance.sliderColor {
        case .accent: return settings.appearance.resolvedAccent
        case .albumArt: return controller.palette.primary
        case .monochrome: return .white.opacity(0.85)
        }
    }

    /// The arranged transport buttons, leaving out any the source cannot carry out.
    private func transportButtons(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(settings.media.controlOrder) { control in
                if controller.supports(control) {
                    transportButton(control)
                }
            }
        }
    }

    /// Pop-out and effects.
    private var trailingCluster: some View {
        HStack(spacing: 6) {
            popOutButton
            effectsButton
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            transportButtons(spacing: 14)
            Spacer(minLength: 0)
        }
        // Room on both sides for the pop-out and effects buttons, so the transport stays
        // centred and can never run underneath them. With shuffle in the row as well it
        // otherwise touched them in the narrower floating window.
        .padding(.horizontal, Self.trailingClusterWidth)
        // Overlaid rather than placed in the row, so adding them does not shift the transport
        // buttons off centre.
        .overlay(alignment: .trailing) { trailingCluster }
    }

    /// Two 26-point buttons and the gap between them.
    private static let trailingClusterWidth: CGFloat = 58

    /// Pops this card out into the floating window, or puts it away again.
    ///
    /// The floating window used to be reachable only from Settings > Media, which is a long
    /// way to go for something you want on and off as you move between screens. This is the
    /// same stored setting, so the button, the Settings switch, and the window's own close
    /// button can never disagree. The card inside the floating window shows this button too,
    /// already in its "open" state, so it doubles as that window's way back in.
    private var popOutButton: some View {
        let isOpen = settings.media.floatingWindow

        return Button {
            settings.media.floatingWindow.toggle()
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        } label: {
            Image(systemName: isOpen ? "pip.exit" : "pip.enter")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOpen ? settings.appearance.resolvedAccent : Color.white.opacity(0.35))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isOpen ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Close the floating Now Playing window" : "Pop Now Playing out into a floating window")
        .accessibilityLabel(isOpen ? "Close floating window" : "Open floating window")
        .animation(Motion.hover, value: isOpen)
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

    /// The toggles are drawn a size down from the transport arrows, as Music draws them.
    private static func isStateControl(_ control: MediaControl) -> Bool {
        control == .shuffle || control == .repeatMode || control == .favorite
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
            TransportSymbol.image(
                symbolName(for: control, isPlaying: isPlaying),
                pointSize: isPlayPause ? 24 : (Self.isStateControl(control) ? 14 : 17)
            )
                .foregroundStyle(foreground(for: control))
                .frame(width: isPlayPause ? 30 : 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(control.title)
        .accessibilityValue(stateDescription(for: control) ?? "")
        .help(stateDescription(for: control).map { "\(control.title): \($0)" } ?? control.title)
    }

    /// Shuffle, repeat and favourite are states, not actions, so they show which state they
    /// are in: the accent when on, dim when off. The others are plain actions and stay white.
    private func foreground(for control: MediaControl) -> Color {
        let accent = settings.appearance.resolvedAccent
        let track = controller.track
        switch control {
        case .playPause: return .white
        case .shuffle: return track?.isShuffling == true ? accent : .white.opacity(0.45)
        case .repeatMode: return (track?.repeatMode ?? .off) != .off ? accent : .white.opacity(0.45)
        case .favorite: return track?.isFavorite == true ? accent : .white.opacity(0.45)
        case .previous, .next: return .white.opacity(0.8)
        }
    }

    /// "On", "Off", "One Song"; nil for a control that is an action.
    private func stateDescription(for control: MediaControl) -> String? {
        let track = controller.track
        switch control {
        case .shuffle: return track?.isShuffling == true ? "On" : "Off"
        case .repeatMode:
            switch track?.repeatMode ?? .off {
            case .off: return "Off"
            case .all: return "All"
            case .one: return "One Song"
            }
        case .favorite: return track?.isFavorite == true ? "Favourite" : "Not a favourite"
        case .playPause, .previous, .next: return nil
        }
    }

    private func symbolName(for control: MediaControl, isPlaying: Bool) -> String {
        switch control {
        case .playPause: return isPlaying ? "pause.fill" : "play.fill"
        case .next: return "forward.fill"
        case .previous: return "backward.fill"
        case .shuffle: return "shuffle"
        case .repeatMode: return controller.track?.repeatMode == .one ? "repeat.1" : "repeat"
        case .favorite: return controller.track?.isFavorite == true ? "heart.fill" : "heart"
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
    @Environment(SettingsStore.self) private var settings

    /// Fast enough that the highlight lands on the beat. Only the strip redraws, and only
    /// while the panel is open with lyrics showing.
    private static let tick: TimeInterval = 0.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
            let elapsed = environment.nowPlaying.lyricsTime(at: context.date)
            let index = lyrics.index(at: elapsed)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    LyricsText.line(lyrics, at: index, time: elapsed)
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

                HStack(spacing: 6) {
                    closedLyricsButton

                    LyricsSheetView.toggleButton(isOpen: false) {
                        environment.nowPlaying.isShowingLyricsSheet = true
                    }
                }
            }
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Lyrics")
    }

    /// Keeps the lyrics on screen under the closed notch, or stops.
    ///
    /// Beside the lyrics themselves, because that is where someone reading them decides they
    /// want to keep reading with the notch shut. The same stored setting as Settings > Media >
    /// Show Lyrics When Closed, so the two cannot disagree; lit in the accent while it is on,
    /// like the pop-out button above it.
    private var closedLyricsButton: some View {
        let isOn = settings.media.showLyricsWhenClosed

        return Button {
            settings.media.showLyricsWhenClosed.toggle()
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
        } label: {
            // Through `TransportSymbol`, not `Image(systemName:)` with a font: drawn that way the
            // glyph came out plain white on and off alike, so the button never showed its state.
            TransportSymbol.image("text.below.photo", pointSize: 10, weight: .semibold)
                .foregroundStyle(isOn ? settings.appearance.resolvedAccent : Color.white.opacity(0.55))
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.14 : 0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Stop showing lyrics when the notch is closed" : "Keep showing lyrics when the notch is closed")
        .accessibilityLabel(isOn ? "Hide lyrics when closed" : "Show lyrics when closed")
        .animation(Motion.hover, value: isOn)
    }

    // MARK: Lines

    private func nextLineText(after index: Int?) -> String {
        let next = (index ?? 0) + 1
        guard lyrics.lines.indices.contains(next) else { return "" }
        return lyrics.lines[next].text
    }
}

/// The karaoke highlight, shared by the strip and the full list.
enum LyricsText {
    /// Builds the line as one concatenated `Text` rather than a stack of word views, so it
    /// wraps, truncates, and kerns exactly as ordinary text does.
    static func line(_ lyrics: Lyrics, at index: Int?, time: TimeInterval) -> Text {
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

    private static func styled(_ word: LyricWord, at time: TimeInterval) -> Text {
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
}

/// Every line of the lyrics, scrolling with the song.
///
/// Opened from the button on the two-line strip, closed from its own. The current line is kept
/// in the middle and highlighted word by word, as in the strip; lines already sung stay
/// readable and lines to come recede. Clicking a synced line seeks the song to it. Unsynced
/// lyrics are simply listed, with nothing highlighted and nothing to click.
struct LyricsSheetView: View {
    let lyrics: Lyrics

    @Environment(AppEnvironment.self) private var environment

    /// Tall enough for about seven lines, short enough that with the artwork above it the
    /// panel stays inside `Metrics.maxPanelHeight`.
    static let height: CGFloat = 176

    private static let tick: TimeInterval = 0.1

    var body: some View {
        let controller = environment.nowPlaying

        TimelineView(.periodic(from: .now, by: Self.tick)) { context in
            let time = controller.lyricsTime(at: context.date)
            let current = lyrics.index(at: time)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            row(line, index: index, current: current, time: time)
                                .id(index)
                        }
                    }
                    .padding(.vertical, Self.height / 2 - 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .onChange(of: current) { _, index in
                    guard let index else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                .onAppear {
                    if let current { proxy.scrollTo(current, anchor: .center) }
                }
            }
            // Lines fade out towards both edges, so the list reads as a window onto the song.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(height: Self.height)
        .overlay(alignment: .topTrailing) {
            Self.toggleButton(isOpen: true) {
                environment.nowPlaying.isShowingLyricsSheet = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lyrics")
    }

    @ViewBuilder
    private func row(_ line: LyricLine, index: Int, current: Int?, time: TimeInterval) -> some View {
        let isCurrent = index == current
        let isSung = current.map { index < $0 } ?? false
        let text: Text = isCurrent
            ? LyricsText.line(lyrics, at: index, time: time)
            : Text(line.text).foregroundStyle(.white.opacity(isSung ? 0.5 : 0.32))

        let label = text
            .font(.system(size: isCurrent ? 14 : 13, weight: isCurrent ? .semibold : .regular))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 30)
            .animation(Motion.hover, value: isCurrent)

        if let timestamp = line.timestamp, environment.nowPlaying.canSeek {
            Button {
                environment.nowPlaying.seek(toLyricsTime: timestamp)
            } label: {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Play from here")
        } else {
            label
        }
    }

    /// The expand button on the strip and the collapse button on the list.
    static func toggleButton(isOpen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isOpen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Show two lines" : "Show all the lyrics")
        .accessibilityLabel(isOpen ? "Show fewer lyrics" : "Show all lyrics")
    }
}

/// Transport symbols, built through AppKit at an exact point size.
///
/// `Image(systemName:)` given an explicit font drew `repeat` and `repeat.1` in plain white in
/// this app, whatever colour they were given, while `shuffle`, `heart` and the arrows took
/// theirs; a symbol at the inherited font took its colour too, as did the same code in a
/// standalone window. So the repeat button never showed that repeat was on. An `NSImage`
/// symbol with a point size, drawn as a template, takes the colour every time, so every
/// transport button is drawn this way rather than special-casing one symbol.
@MainActor
enum TransportSymbol {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .medium) -> Image {
        let key = "\(name)|\(pointSize)|\(weight.rawValue)"
        if let cached = cache[key] {
            return Image(nsImage: cached).renderingMode(.template)
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        guard let symbol else { return Image(systemName: name) }
        symbol.isTemplate = true
        cache[key] = symbol
        return Image(nsImage: symbol).renderingMode(.template)
    }
}
