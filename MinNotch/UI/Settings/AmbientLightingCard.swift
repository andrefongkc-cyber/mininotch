import SwiftUI

/// Settings > Appearance > Ambient Lighting.
///
/// Split out of `AppearanceSettingsView` because it is the largest single group in the app
/// and carries its own live preview, which is a view rather than a row.
struct AmbientLightingCard: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    /// Recent taps of the Tap button, for tap tempo.
    @State private var taps: [Date] = []

    var body: some View {
        @Bindable var settings = settings
        let glow = settings.appearance.ambientGlow

        // One card rather than five. Splitting it into separate groups scattered the
        // controls for a single effect down the length of the pane, which made comparing a
        // style against its own colour and speed a scrolling exercise.
        SettingsCard(header: "Ambient Lighting", footer: audioFooter) {
            SettingsRow(
                title: "Enable Ambient Glow",
                subtitle: "The Now Playing card cycles this with the visualizer, and its menu switches style.",
                systemImage: "light.beacon.max"
            ) {
                SettingsToggle(isOn: $settings.appearance.ambientGlow.isEnabled)
            }

            SettingsDivider()

            preview(glow)

            SettingsDivider()

            SettingsRow(
                title: "Style",
                subtitle: glow.style.detail,
                systemImage: "sparkles",
                isEnabled: glow.isEnabled
            ) {
                InlinePicker(selection: $settings.appearance.ambientGlow.style) {
                    ForEach(AmbientGlowStyleKind.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            if glow.style.usesColorMode {
                SettingsDivider()

                SettingsRow(title: "Color", systemImage: "paintpalette", isEnabled: glow.isEnabled) {
                    InlinePicker(selection: $settings.appearance.ambientGlow.colorMode) {
                        ForEach(GlowColorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                if glow.colorMode == .staticColor {
                    SettingsDivider()

                    SettingsRow(title: "Static Color", systemImage: "eyedropper", isEnabled: glow.isEnabled) {
                        ColorPicker(
                            "",
                            selection: Binding(
                                get: { settings.appearance.ambientGlow.staticColor.color },
                                set: { settings.appearance.ambientGlow.staticColor = RGBAColor($0) }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                }
            }

            SettingsDivider()

            SettingsRow(
                title: "Where It Shows",
                subtitle: "Any combination. Only the one currently on screen is drawn.",
                systemImage: "square.on.square",
                isEnabled: glow.isEnabled
            ) {
                HStack(spacing: 4) {
                    ForEach(AmbientGlowPlacement.allCases) { placement in
                        placementChip(placement, isEnabled: glow.isEnabled)
                    }
                }
            }

            SettingsDivider()

            SettingsRow(title: "Intensity", systemImage: "sun.max", isEnabled: glow.isEnabled) {
                ValueSlider(
                    value: $settings.appearance.ambientGlow.intensity,
                    range: 0.1...1,
                    step: 0.05
                ) { String(format: "%.0f%%", $0 * 100) }
            }

            SettingsDivider()

            SettingsRow(title: "Speed", systemImage: "hare", isEnabled: glow.isEnabled) {
                ValueSlider(
                    value: $settings.appearance.ambientGlow.speed,
                    range: 0...1,
                    step: 0.05
                ) { String(format: "%.0f%%", $0 * 100) }
            }

            SettingsDivider()

            SettingsRow(
                title: "Tempo",
                subtitle: tempoSubtitle(glow),
                systemImage: "metronome",
                isEnabled: glow.isEnabled
            ) {
                InlinePicker(selection: $settings.appearance.ambientGlow.tempoSource) {
                    ForEach(GlowTempoSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
            }

            if glow.tempoSource == .manual {
                SettingsDivider()

                SettingsRow(
                    title: "Beats per Minute",
                    subtitle: "Or tap along to the music; the beats then land on your taps.",
                    systemImage: "hand.tap",
                    isEnabled: glow.isEnabled
                ) {
                    HStack(spacing: 8) {
                        ValueSlider(
                            value: $settings.appearance.ambientGlow.manualBPM,
                            range: AmbientGlowSettings.bpmRange,
                            step: 1,
                            format: { "\(Int($0)) bpm" },
                            width: 110
                        )
                        Button("Tap", action: tapTempo)
                            .controlSize(.small)
                            .help("Tap along with the music, at least twice")
                    }
                }
            }

            SettingsDivider()

            SettingsRow(
                title: "Glow Radius",
                subtitle: "Capped automatically on the closed pill, which is too thin to take a wide blur.",
                systemImage: "circle.dashed",
                isEnabled: glow.isEnabled
            ) {
                ValueSlider(
                    value: $settings.appearance.ambientGlow.glowRadius,
                    range: 2...28,
                    step: 1
                ) { "\(Int($0)) pt" }
            }

            SettingsDivider()

            SettingsRow(
                title: "Follow the Beat",
                subtitle: "Analyse what is playing so the light tracks the music instead of animating on its own.",
                systemImage: "waveform.badge.magnifyingglass",
                badge: FeatureFlag.audioReactiveGlow.badge,
                isEnabled: glow.isEnabled
            ) {
                SettingsToggle(isOn: $settings.appearance.ambientGlow.isAudioReactive)
            }

            if glow.isAudioReactive, glow.isEnabled {
                SettingsDivider()

                SettingsRow(
                    title: "What It Is Hearing",
                    subtitle: hearingSubtitle,
                    systemImage: "waveform"
                ) {
                    AudioLevelMeter(analyzer: environment.audioAnalyzer)
                }
            }

            if environment.audioAnalyzer.failure != nil, glow.isAudioReactive {
                SettingsDivider()

                SettingsRow(
                    title: "Try Again",
                    subtitle: "Ask for the system audio permission once more.",
                    systemImage: "arrow.clockwise"
                ) {
                    Button("Retry") { environment.audioAnalyzer.retry() }
                        .controlSize(.small)
                }
            }

            SettingsDivider()

            SettingsRow(
                title: "Pause in Low Power Mode",
                systemImage: "battery.25percent",
                isEnabled: glow.isEnabled
            ) {
                SettingsToggle(isOn: $settings.appearance.ambientGlow.pauseInLowPowerMode)
            }
        }
    }

    /// Placement is a multi-select, so it gets chips rather than a picker.
    private func placementChip(_ placement: AmbientGlowPlacement, isEnabled: Bool) -> some View {
        @Bindable var settings = settings
        let isOn = settings.appearance.ambientGlow.placements.contains(placement)

        return Button {
            var placements = settings.appearance.ambientGlow.placements
            if isOn { placements.remove(placement) } else { placements.insert(placement) }
            settings.appearance.ambientGlow.placements = placements
        } label: {
            Image(systemName: placement.symbolName)
                .font(.system(size: 12))
                .frame(width: 30, height: 22)
                .foregroundStyle(isOn ? Color.white : Palette.secondaryText)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Palette.controlAccent : Palette.separator.opacity(0.3))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(placement.title)
        .disabled(!isEnabled)
    }

    /// A miniature of the current settings, so styles can be compared without opening the
    /// notch and playing something for each one.
    private func preview(_ glow: AmbientGlowSettings) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)

            AmbientGlowView(
                outline: .roundedRect(cornerRadius: 10),
                settings: previewSettings(glow),
                palette: environment.nowPlaying.palette,
                // Always animates here, so the preview shows the style even with nothing
                // playing. The real surfaces settle when playback stops.
                isPlaying: true,
                audio: environment.audioAnalyzer.current == nil ? nil : environment.audioAnalyzer,
                tempo: environment.glowTempo(),
                // Roughly the preview box; only used to cap the blur.
                sizeHint: CGSize(width: 300, height: 50)
            )
            .padding(18)

            if !glow.isEnabled {
                Text("Off")
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(height: 86)
        .opacity(glow.isEnabled ? 1 : 0.5)
        .padding(.horizontal, Metrics.cardHorizontalPadding)
        .padding(.vertical, 10)
    }

    /// The preview ignores the enabled switch, since it is showing what the style looks like
    /// rather than whether it is on. It draws against a rounded square because that reads at
    /// this size; the glow itself only appears on the notch.
    private func previewSettings(_ glow: AmbientGlowSettings) -> AmbientGlowSettings {
        var preview = glow
        preview.isEnabled = true
        preview.glowRadius = min(glow.glowRadius, 14)
        return preview
    }

    /// Says plainly whether the light is following real sound or animating, because the two are
    /// indistinguishable by eye and the first thing anyone asks is which one they are looking at.
    private func tempoSubtitle(_ glow: AmbientGlowSettings) -> String {
        let base = "Used while the glow is not following the beat."
        switch glow.tempoSource {
        case .speed:
            return base
        case .manual:
            return base
        case .song:
            if let bpm = environment.nowPlaying.track?.beatsPerMinute {
                return "\(base) This song is tagged \(Int(bpm)) bpm."
            }
            return "\(base) Uses the BPM Music keeps for a track, and the Speed slider for a song without one. Spotify shares none."
        }
    }

    /// Tap tempo: the median gap between recent taps, and the last tap as where a beat falls.
    ///
    /// A pause of more than two seconds starts again, so a new tempo is never averaged with the
    /// last one. The median rather than the mean, because one late tap would otherwise pull
    /// the whole tempo with it.
    private func tapTempo() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2 { taps.removeAll() }
        taps.append(now)
        taps = Array(taps.suffix(8))
        guard taps.count >= 2 else { return }

        let gaps = zip(taps, taps.dropFirst()).map { $1.timeIntervalSince($0) }.sorted()
        let median = gaps[gaps.count / 2]
        guard median > 0 else { return }
        let bpm = min(max((60 / median).rounded(), AmbientGlowSettings.bpmRange.lowerBound), AmbientGlowSettings.bpmRange.upperBound)
        settings.appearance.ambientGlow.manualBPM = bpm
        settings.appearance.ambientGlow.tempoSource = .manual
        environment.tappedBeatOrigin = now.timeIntervalSinceReferenceDate
    }

    private var hearingSubtitle: String {
        if environment.audioAnalyzer.failure != nil {
            return "Not listening, so the light is animating on its own."
        }
        guard environment.audioAnalyzer.isRunning else {
            return "Starting up. Until it does, the light animates on its own while something plays."
        }
        return "Live, from the system audio. Play something and these move; in silence they stay down."
    }

    private var audioFooter: String {
        if let failure = environment.audioAnalyzer.failure {
            return failure.message + " Switch Follow the Beat off and on to try again."
        }
        if environment.audioAnalyzer.isRunning {
            let latency = Int(environment.audioAnalyzer.outputLatency * 1000)
            return "Listening. Your output device reports \(latency) ms of buffering, which is subtracted from lyric timing."
        }
        return "Following the beat reads system audio through a Core Audio tap, which asks for the system audio recording permission. That is a separate permission from the microphone and from screen recording. Nothing is recorded or written anywhere: the audio becomes a handful of numbers and is discarded."
    }
}

/// Eight live bars of what the audio tap is hearing.
///
/// The point is proof, not decoration: the glow cannot be judged by eye for whether it is
/// following sound, since a plausible animation and a real analysis look alike once blurred.
/// These sit still in silence and move with whatever is playing. Drawn only while the Ambient
/// Lighting card is on screen, and reading the analysis that is already being published.
private struct AudioLevelMeter: View {
    let analyzer: AudioAnalyzer

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !analyzer.isRunning)) { _ in
            let bands = analyzer.current?.bands ?? []

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<GlowInput.bandCount, id: \.self) { index in
                    let level = index < bands.count ? bands[index] : 0
                    Capsule()
                        .fill(level > 0.02 ? Palette.controlAccent : Palette.separator)
                        .frame(width: 3, height: max(2, 18 * level))
                }
            }
            .frame(width: 44, height: 18, alignment: .bottom)
            .accessibilityHidden(true)
        }
    }
}
