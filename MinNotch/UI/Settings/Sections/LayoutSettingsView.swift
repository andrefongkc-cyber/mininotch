import SwiftUI

/// Settings > Layout: what the notch shows, and where, arranged on a picture of it.
///
/// The closed pill, the open panel's widgets and top bar, and the Now Playing controls used to
/// be arranged in three different panes with lanes of text chips. They are one question, what
/// goes where on the notch, so they are one pane, and each is drawn as the surface it arranges.
struct LayoutSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(
            title: "Layout",
            subtitle: "Drag icons into the notch to choose what it shows and where, or click one in a tray to add it. Drag an icon back to its tray, or hover it and click ×, to take it out."
        ) {
            SettingsCard(
                header: "Closed Pill",
                footer: "The middle is the camera housing: nothing is drawn there, and clicks go through it. Both sides are kept the same width, so the pill stays centred on the camera."
            ) {
                SettingsRow(
                    title: "Show Indicators When Closed",
                    subtitle: "Widen the pill either side of the notch to show battery and what is playing.",
                    systemImage: "rectangle.expand.vertical"
                ) {
                    SettingsToggle(isOn: $settings.general.extendPillForIndicators)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Arrangement",
                    subtitle: "What the closed pill shows either side of the notch. Album art and the song appear while a song is loaded, the playing indicator only while it plays, and a live activity is a timer, a download or a device connecting.",
                    systemImage: "rectangle.split.3x1"
                ) { EmptyView() }

                IconLayoutEditor(
                    surface: .closedPill,
                    leading: $settings.general.pillLeading,
                    trailing: $settings.general.pillTrailing,
                    catalogue: PillIndicator.allCases,
                    inactiveCaption: settings.general.extendPillForIndicators
                        ? nil
                        : "Indicators are off, so the closed pill shows nothing",
                    // The miniature shows what the pill is showing: this cover, this song, this
                    // battery. Anything with nothing to show right now keeps its symbol, faded.
                    livePreview: { indicator in
                        let pill = CollapsedPillContent.live(environment: environment, settings: settings, isExtended: true)
                        guard pill.hasContent(indicator) else { return nil }
                        return AnyView(PillIndicatorView(indicator: indicator, content: pill))
                    }
                )
                .padding(.horizontal, Metrics.cardHorizontalPadding)
                .padding(.bottom, 12)

                SettingsDivider()

                SettingsRow(
                    title: "Song Shows",
                    subtitle: "What the Song in the closed pill says. Long names are cut short.",
                    systemImage: "textformat",
                    isEnabled: settings.general.extendPillForIndicators
                ) {
                    InlinePicker(selection: $settings.general.pillSongText) {
                        ForEach(PillSongText.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                }
            }

            SettingsCard(
                header: "Live Activities",
                footer: "Live activities appear in the closed pill where Live Activity is placed above. Swipe left or right on the closed pill with two fingers to move between several, and up to put a notice away."
            ) {
                SettingsRow(
                    title: "Downloads",
                    subtitle: downloadsSubtitle,
                    systemImage: "arrow.down.circle"
                ) {
                    SettingsToggle(isOn: $settings.general.showDownloadActivity)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Devices Connecting",
                    subtitle: "Show the charge of AirPods and other accessories for a few seconds when they connect.",
                    systemImage: "airpodspro"
                ) {
                    SettingsToggle(isOn: $settings.general.announceConnectedDevices)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Upcoming Meetings",
                    subtitle: "Count down to your next calendar event. Zoom, Meet, Teams, Webex and FaceTime links get a Join button in the Calendar tab.",
                    systemImage: "video",
                    isEnabled: settings.calendar.enabled
                ) {
                    SettingsToggle(isOn: $settings.calendar.showMeetingCountdown)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Minutes Before",
                    subtitle: "How long before a meeting the countdown appears.",
                    systemImage: "clock.badge",
                    isEnabled: settings.calendar.enabled && settings.calendar.showMeetingCountdown
                ) {
                    ValueSlider(
                        value: $settings.calendar.meetingLeadMinutes,
                        range: CalendarSettings.meetingLeadRange,
                        step: 1
                    ) { "\(Int($0)) min" }
                }
            }

            SettingsCard(
                header: "Open Panel",
                footer: "Tabs can be moved but not removed; switch a widget off above to hide its tab. When one side of the top bar is full, what does not fit moves across the notch rather than hiding behind the camera."
            ) {
                SettingsRow(
                    title: "Widgets",
                    subtitle: "Click to switch a widget on or off. Each one that is on gets a tab in the top bar.",
                    systemImage: "square.grid.2x2"
                ) { EmptyView() }

                WidgetTiles()
                    .padding(.horizontal, Metrics.cardHorizontalPadding)
                    .padding(.bottom, 12)

                SettingsDivider()

                SettingsRow(
                    title: "Top Bar",
                    subtitle: "What the open panel shows either side of the notch.",
                    systemImage: "rectangle.topthird.inset.filled"
                ) { EmptyView() }

                IconLayoutEditor(
                    surface: .topBar,
                    leading: shownItems($settings.appearance.topStripLeading),
                    trailing: shownItems($settings.appearance.topStripTrailing),
                    catalogue: topBarCatalogue,
                    // Tabs and debug buttons go with their feature or setting, not with a drag.
                    canRemove: { $0.tab == nil && !$0.isDebug },
                    // Settings and battery have always lived on the right.
                    sideForNewItem: { $0.tab == nil ? .trailing : .leading }
                )
                .padding(.horizontal, Metrics.cardHorizontalPadding)
                .padding(.bottom, 12)
            }

            SettingsCard(
                header: "Now Playing Controls",
                footer: "The order here is the order on the Now Playing card. Shuffle and repeat work with Apple Music and Spotify; favourite works with Apple Music."
            ) {
                SettingsRow(
                    title: "Controls",
                    subtitle: "The buttons under the scrubber, left to right.",
                    systemImage: "playpause"
                ) { EmptyView() }

                IconLayoutEditor(
                    surface: .controls,
                    leading: $settings.media.controlOrder,
                    trailing: nil,
                    catalogue: MediaControl.allCases,
                    isProminent: { $0 == .playPause }
                )
                .padding(.horizontal, Metrics.cardHorizontalPadding)
                .padding(.bottom, 12)
            }
        }
    }

    private var downloadsSubtitle: String {
        if settings.general.showDownloadActivity, !environment.downloads.hasAccess {
            return "MinNotch cannot read your Downloads folder. Allow it under Privacy & Security > Files and Folders."
        }
        return "Show how far along a download is, from Safari, Chrome, Firefox and most other browsers. Reads your Downloads folder."
    }

    /// Tabs for features that are switched on, plus settings and battery, and the debug buttons
    /// while their setting is on.
    private var topBarCatalogue: [TopStripItem] {
        NotchWidgetRegistry.shownTabs(settings).map(TopStripItem.init)
            + [.settings, .battery]
            + (settings.advanced.showDebugButtons ? [.whatsNew, .tutorial] : [])
    }

    /// One side of the top bar with the tabs of switched-off features left out of the editor.
    ///
    /// They stay in the saved list, at the end, so switching the feature back on returns its tab
    /// to the side it was on rather than to the default.
    private func shownItems(_ items: Binding<[TopStripItem]>) -> Binding<[TopStripItem]> {
        let catalogue = topBarCatalogue
        return Binding(
            get: { items.wrappedValue.filter(catalogue.contains) },
            set: { shown in
                let hidden = items.wrappedValue.filter { !catalogue.contains($0) }
                items.wrappedValue = shown + hidden
            }
        )
    }
}

/// One tile per widget the open panel can show, lit while it is on.
///
/// A click writes the same setting as the switch in that feature's own pane, so the two can
/// never disagree. System has no switch: it is the panel's fallback when everything else is
/// off, so it is shown, always on, and says so.
struct WidgetTiles: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        WrappingRow(spacing: 8) {
            ForEach(NotchWidgetRegistry.all.filter(\.flag.isEnabled)) { descriptor in
                tile(descriptor.tab, isOn: descriptor.isEnabled(settings))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ tab: NotchTab, isOn: Bool) -> some View {
        let accent = settings.appearance.resolvedAccent
        let canToggle = toggle(for: tab) != nil

        return VStack(spacing: 5) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? .white : Palette.secondaryText)
                .frame(width: 46, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOn ? accent : Palette.paneBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isOn ? .clear : Palette.separator, lineWidth: 1)
                )
            Text(tab.title)
                .font(.system(size: 10))
                .foregroundStyle(isOn ? Palette.primaryText : Palette.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 70)
        .contentShape(Rectangle())
        .onTapGesture { toggle(for: tab)?() }
        .help(canToggle
              ? "\(tab.title) is \(isOn ? "on" : "off"). Click to switch it \(isOn ? "off" : "on")."
              : "\(tab.title) is always available.")
        .animation(Motion.hover, value: isOn)
    }

    /// Flips the setting behind a widget, or nil for one that cannot be switched off.
    private func toggle(for tab: NotchTab) -> (() -> Void)? {
        switch tab {
        case .media: return { settings.media.enabled.toggle() }
        case .calendar: return { settings.calendar.enabled.toggle() }
        case .system: return nil
        case .shelf: return { settings.shelf.enabled.toggle() }
        case .clipboard: return { settings.advanced.clipboardHistoryEnabled.toggle() }
        case .links: return { settings.advanced.linkShelfEnabled.toggle() }
        case .timer: return { settings.timer.enabled.toggle() }
        }
    }
}
