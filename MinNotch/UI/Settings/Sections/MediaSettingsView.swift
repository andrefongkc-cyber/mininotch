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
                    subtitle: "Also show Now Playing in a small window above other apps. Drag it anywhere; it remembers where you put it.",
                    systemImage: "macwindow.on.rectangle",
                    isEnabled: settings.media.enabled
                ) {
                    SettingsToggle(isOn: $settings.media.floatingWindow)
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
                header: "Controls",
                footer: "Drag to reorder, or drag out to remove. The order here is the order on the Now Playing card."
            ) {
                SlotLayoutEditor(
                    zones: [
                        .init(
                            id: "controls",
                            title: "Shown, left to right",
                            items: $settings.media.controlOrder,
                            emptyHint: "No transport controls"
                        )
                    ],
                    paletteTitle: "Not Shown",
                    paletteHint: "Drag here to remove"
                )
                .padding(.horizontal, Metrics.cardHorizontalPadding)
                .padding(.vertical, 6)

                if settings.media.controlOrder.contains(where: { !$0.isImplemented }) {
                    SettingsDivider()

                    SettingsRow(
                        title: "Not Yet Wired Up",
                        subtitle: "Shuffle, repeat, and favourite are arranged here but have no command behind them yet, so they will not appear on the card.",
                        systemImage: "exclamationmark.triangle",
                        badge: .comingSoon
                    ) { EmptyView() }
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

            SettingsCard(header: "Coming Soon") {
                SettingsRow(
                    title: "Sneak Peek on Track Change",
                    subtitle: "Briefly expand the notch when a new track starts.",
                    systemImage: "rectangle.expand.vertical",
                    badge: .comingSoon
                ) {
                    SettingsToggle(isOn: $settings.media.sneakPeekOnTrackChange)
                        .comingSoon()
                }
            }
        }
    }

    /// Says whether the compensation is actually doing anything, since it depends on the
    /// ambient lighting's audio tap being switched on in Appearance.
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
