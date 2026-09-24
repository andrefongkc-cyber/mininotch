import SwiftUI

struct MediaSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(title: "Media") {
            SettingsCard(header: "Source") {
                SettingsRow(
                    title: "Show Now Playing",
                    systemImage: "music.note"
                ) {
                    SettingsToggle(isOn: $settings.media.enabled)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Player",
                    subtitle: "Automatic follows whichever supported player is active.",
                    systemImage: "app.badge",
                    isEnabled: settings.media.enabled
                ) {
                    InlinePicker(selection: $settings.media.preferredSource) {
                        ForEach(MediaSourceKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "System Now Playing",
                    subtitle: environment.nowPlaying.systemSourceStatus,
                    systemImage: "waveform"
                ) {
                    EmptyView()
                }

                if AppleScriptRunner.shared.isAuthorizationDenied {
                    SettingsDivider()

                    SettingsRow(
                        title: "Automation Permission",
                        subtitle: "macOS is blocking MinNotch from controlling Music and Spotify.",
                        systemImage: "exclamationmark.triangle"
                    ) {
                        Button("Open Settings") {
                            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                            if let url { NSWorkspace.shared.open(url) }
                        }
                        .controlSize(.small)
                    }
                }
            }

            SettingsCard(
                header: "Lyrics",
                footer: settings.media.lyricsSource.usesNetwork
                    ? "Looking up online sends the track title, artist, album, and length to lrclib.net. Nothing else is sent, and no account is needed."
                    : "Streamed tracks almost never carry lyrics locally, so this finds very little on its own. Switch to Look Up Online to fetch synced lyrics."
            ) {
                SettingsRow(
                    title: "Show Lyrics",
                    subtitle: "Display the current line under the track info when lyrics are available.",
                    systemImage: "quote.bubble",
                    badge: FeatureFlag.lyrics.badge,
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: Binding(
                        get: { settings.media.showLyrics },
                        set: { newValue in
                            settings.media.showLyrics = newValue
                            environment.nowPlaying.reloadLyricsIfNeeded()
                        }
                    ))
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show Lyrics When Closed",
                    subtitle: "The line being sung, under the closed notch, while a song with synced lyrics plays.",
                    systemImage: "text.below.photo",
                    isEnabled: settings.media.enabled && settings.media.showLyrics
                ) {
                    SettingsToggle(isOn: $settings.media.showLyricsWhenClosed)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Timing Offset",
                    subtitle: "Shift lyrics earlier or later. Lyric files are timed by hand and disagree between sources.",
                    systemImage: "timer",
                    isEnabled: settings.media.enabled && settings.media.showLyrics
                ) {
                    ValueSlider(
                        value: $settings.media.lyricsOffset,
                        range: -2...2,
                        step: 0.1
                    ) { value in
                        value == 0 ? "None" : String(format: "%+.1f s", value)
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Use Audio Clock",
                    subtitle: audioClockSubtitle,
                    systemImage: "waveform.badge.magnifyingglass",
                    isEnabled: settings.media.enabled && settings.media.showLyrics
                ) {
                    SettingsToggle(isOn: $settings.media.useAudioClockForLyrics)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Fix Timing Automatically",
                    subtitle: matchToAudioSubtitle,
                    systemImage: "waveform.and.person.filled",
                    isEnabled: settings.media.enabled && settings.media.showLyrics
                ) {
                    SettingsToggle(isOn: $settings.media.matchLyricsToAudio)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Lyrics Source",
                    subtitle: "Where to look when your player has no lyrics stored.",
                    systemImage: "magnifyingglass",
                    isEnabled: settings.media.enabled && settings.media.showLyrics
                ) {
                    InlinePicker(selection: Binding(
                        get: { settings.media.lyricsSource },
                        set: { newValue in
                            settings.media.lyricsSource = newValue
                            environment.nowPlaying.reloadLyricsIfNeeded()
                        }
                    )) {
                        ForEach(LyricsSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                }
            }

            SettingsCard(header: "Display") {
                SettingsRow(
                    title: "Floating Window",
                    subtitle: "Also show Now Playing in a small window above other apps. Drag it anywhere; it remembers where you put it. The pop-out button on the Now Playing card does the same.",
                    systemImage: "macwindow.on.rectangle",
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: $settings.media.floatingWindow)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Sneak Peek on Track Change",
                    subtitle: "When a new song starts, the closed notch drops down for a moment to show what it is.",
                    systemImage: "rectangle.expand.vertical",
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: $settings.media.sneakPeekOnTrackChange)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Sneak Peek Length",
                    subtitle: "How long the song stays on screen after it changes.",
                    systemImage: "timer",
                    isEnabled: settings.media.enabled && settings.media.sneakPeekOnTrackChange
                ) {
                    ValueSlider(
                        value: $settings.media.sneakPeekDuration,
                        range: MediaSettings.sneakPeekDurationRange,
                        step: 0.5
                    ) { String(format: "%.1f s", $0) }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show Up Next",
                    subtitle: "Off for now. Music tells other apps a playlist is shuffling when it is playing in order, so the list was wrong too often to be worth showing.",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    badge: FeatureFlag.upNext.badge,
                    isEnabled: settings.media.enabled && FeatureFlag.upNext.isEnabled
                ) {
                    SettingsToggle(isOn: $settings.media.showUpNext)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show Elapsed and Remaining Time",
                    systemImage: "clock",
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: $settings.media.showTimecodes)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show Which App Is Playing",
                    subtitle: "A small icon of the app on the corner of the artwork.",
                    systemImage: "app.badge",
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: $settings.media.showSourceBadge)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Tint From Artwork",
                    subtitle: "Wash the panel with the album's dominant colour.",
                    systemImage: "photo",
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: $settings.media.tintFromArtwork)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Refresh Interval",
                    subtitle: "How often the position is re-read. Track changes update instantly regardless.",
                    systemImage: "arrow.clockwise",
                    isEnabled: settings.media.enabled
                ) {
                    ValueSlider(
                        value: $settings.media.pollInterval,
                        range: 0.5...5,
                        step: 0.5
                    ) { String(format: "%.1f s", $0) }
                }
            }

            SettingsCard(
                header: "Visualizer",
                footer: "The bars are an animation rather than an analysis of the audio. Ambient Lighting, in Appearance, can follow the real beat. The Now Playing card has one button that cycles the two effects."
            ) {
                SettingsRow(
                    title: "Show Visualizer",
                    subtitle: "Animated bars over the artwork, coloured from the album.",
                    systemImage: "waveform.path",
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: $settings.media.showVisualizer)
                }

            }

        }
    }

    /// Says whether the compensation is actually doing anything, since it depends on the
    /// ambient lighting's audio tap being switched on in Appearance.
    /// Says what the measurement is doing right now, because a correction the user cannot see
    /// is indistinguishable from a setting that does nothing.
    private var matchToAudioSubtitle: String {
        guard settings.media.matchLyricsToAudio else {
            return "For lyrics that run early or late: listens for where the singing starts and moves the lyrics to match. Lyrics only; the glow's Follow the Beat is separate. Uses the system audio permission."
        }
        let sync = environment.nowPlaying.lyricsSync
        if let failure = environment.audioAnalyzer.failure {
            return "Waiting on the system audio: \(failure.message)"
        }
        if let offset = sync.offset {
            return String(format: "Lyrics moved %+.2f s to match the singing, from %d lines.", offset, sync.matchCount)
        }
        if sync.matchCount > 0 {
            return "Heard the singing start on \(sync.matchCount) of the \(LyricsSyncCalibrator.minimumMatches) lines it needs. The lyrics stay where they are until they agree."
        }
        return "Listening for where the singing starts. The lyrics only move once several lines agree, so on time lyrics are left alone."
    }

    private var audioClockSubtitle: String {
        let latency = environment.nowPlaying.lyricsLatencyCompensation
        guard latency > 0 else {
            return "Subtract your output device's buffering. Needs Follow the Beat on, in Appearance > Ambient Lighting."
        }
        return String(format: "Compensating for %.0f ms of output buffering.", latency * 1000)
    }

    private func symbolName(for control: MediaControl) -> String {
        switch control {
        case .shuffle: return "shuffle"
        case .previous: return "backward.end"
        case .playPause: return "playpause"
        case .next: return "forward.end"
        case .repeatMode: return "repeat"
        case .favorite: return "heart"
        }
    }
}
