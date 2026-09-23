import SwiftUI

struct CalendarSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    private var service: CalendarService { environment.calendarService }

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(title: "Calendar") {
            if !service.hasAccess {
                SettingsCard(
                    header: "Access",
                    footer: "MinNotch reads events to display them, and writes only what you create with Quick Add. Nothing is sent anywhere."
                ) {
                    SettingsRow(
                        title: "Calendar Access",
                        subtitle: accessDescription,
                        systemImage: "lock"
                    ) {
                        Button(needsSystemSettings ? "Open Settings" : "Allow…") {
                            if needsSystemSettings {
                                service.openPrivacySettings()
                            } else {
                                service.requestAccess()
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            SettingsCard(header: "Widget") {
                SettingsRow(title: "Show Calendar", systemImage: "calendar") {
                    SettingsToggle(isOn: $settings.calendar.enabled)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Grid",
                    subtitle: "Show the current week or the whole month.",
                    systemImage: "square.grid.3x3",
                    isEnabled: settings.calendar.enabled
                ) {
                    InlinePicker(selection: $settings.calendar.viewMode) {
                        ForEach(CalendarViewMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Start Week on Monday",
                    subtitle: "Otherwise MinNotch follows your region's first weekday.",
                    systemImage: "calendar.day.timeline.left",
                    isEnabled: settings.calendar.enabled
                ) {
                    SettingsToggle(isOn: $settings.calendar.forceMondayFirst)
                }
            }

            SettingsCard(header: "Events") {
                SettingsRow(
                    title: "Show All-Day Events",
                    systemImage: "sun.max",
                    isEnabled: settings.calendar.enabled
                ) {
                    SettingsToggle(isOn: $settings.calendar.showAllDayEvents)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Look Ahead",
                    subtitle: "How far into the future the upcoming list reaches.",
                    systemImage: "arrow.forward.to.line",
                    isEnabled: settings.calendar.enabled
                ) {
                    ValueSlider(
                        value: Binding(
                            get: { Double(settings.calendar.upcomingDayCount) },
                            set: { settings.calendar.upcomingDayCount = Int($0) }
                        ),
                        range: 1...14,
                        step: 1
                    ) { $0 == 1 ? "1 day" : "\(Int($0)) days" }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Rows Shown",
                    subtitle: "Anything beyond this scrolls inside the panel.",
                    systemImage: "list.bullet",
                    isEnabled: settings.calendar.enabled
                ) {
                    ValueSlider(
                        value: Binding(
                            get: { Double(settings.calendar.maxVisibleEvents) },
                            set: { settings.calendar.maxVisibleEvents = Int($0) }
                        ),
                        range: 2...12,
                        step: 1
                    ) { "\(Int($0))" }
                }
            }

            if service.hasAccess {
                calendarsCard
            }

            SettingsCard(
                header: "Reminders",
                footer: remindersFooter
            ) {
                SettingsRow(
                    title: "Show Reminders",
                    subtitle: "Mix reminders that are due into the upcoming list.",
                    systemImage: "checklist"
                ) {
                    SettingsToggle(isOn: Binding(
                        get: { settings.calendar.showReminders },
                        set: { newValue in
                            settings.calendar.showReminders = newValue
                            // Asking only when it is switched on keeps the prompt tied to a
                            // deliberate action rather than to launching the app.
                            if newValue, !service.hasRemindersAccess {
                                service.requestRemindersAccess()
                            } else {
                                service.refreshReminders()
                            }
                        }
                    ))
                }

                SettingsDivider()

                SettingsRow(
                    title: "Hide Completed Reminders",
                    systemImage: "checkmark.circle",
                    isEnabled: settings.calendar.showReminders
                ) {
                    SettingsToggle(isOn: Binding(
                        get: { settings.calendar.hideCompletedReminders },
                        set: { newValue in
                            settings.calendar.hideCompletedReminders = newValue
                            service.refreshReminders()
                        }
                    ))
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show Reminders Without a Date",
                    subtitle: "List them after everything that is due.",
                    systemImage: "tray",
                    isEnabled: settings.calendar.showReminders
                ) {
                    SettingsToggle(isOn: $settings.calendar.showUndatedReminders)
                }

                if settings.calendar.showReminders, !service.hasRemindersAccess {
                    SettingsDivider()

                    SettingsRow(
                        title: "Reminders Access",
                        subtitle: "MinNotch needs permission before it can show your reminders.",
                        systemImage: "lock"
                    ) {
                        Button("Allow…") { service.requestRemindersAccess() }
                            .controlSize(.small)
                    }
                }
            }

            SettingsCard(
                header: "Quick Add",
                footer: "Events are created in your default calendar starting at the next half hour, or at 9 AM on the day picked in the grid. Reminders are due at the same time."
            ) {
                SettingsRow(
                    title: "Quick Add Field",
                    subtitle: "Create an event or reminder straight from the notch.",
                    systemImage: "plus.circle",
                    isEnabled: settings.calendar.enabled
                ) {
                    SettingsToggle(isOn: $settings.calendar.enableQuickAdd)
                }
            }
        }
    }

    private var remindersFooter: String {
        switch service.remindersAuthorizationStatus {
        case .denied:
            return "Reminders access is denied. Turn MinNotch on under Privacy & Security > Reminders."
        case .fullAccess:
            return "Reminders due in the same window as your events appear in the list, and can be ticked off from the notch."
        default:
            return "Turning this on asks for Reminders access."
        }
    }

    private var needsSystemSettings: Bool {
        service.authorizationStatus == .denied || service.promptDidNotAppear
    }

    private var accessDescription: String {
        switch service.authorizationStatus {
        case .denied: return "Denied. Turn MinNotch on under Privacy & Security > Calendars."
        case .restricted: return "Restricted by a profile on this Mac."
        case .writeOnly: return "MinNotch has write-only access and cannot read your events."
        default:
            return service.promptDidNotAppear
                ? "macOS did not show the permission dialog. Grant access in System Settings."
                : "Not granted yet."
        }
    }

    /// One toggle per calendar, grouped by account the way Calendar.app groups them.
    private var calendarsCard: some View {
        @Bindable var settings = settings
        let grouped = Dictionary(grouping: service.calendars, by: \.sourceTitle)
            .sorted { $0.key < $1.key }

        return VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            ForEach(grouped, id: \.key) { source, calendars in
                SettingsCard(header: source) {
                    ForEach(Array(calendars.enumerated()), id: \.element.id) { index, calendar in
                        if index > 0 { SettingsDivider() }

                        SettingsRow(title: calendar.title, accentDot: calendar.color) {
                            SettingsToggle(isOn: Binding(
                                get: { !settings.calendar.hiddenCalendarIdentifiers.contains(calendar.id) },
                                set: { isVisible in
                                    var hidden = settings.calendar.hiddenCalendarIdentifiers
                                    if isVisible { hidden.remove(calendar.id) } else { hidden.insert(calendar.id) }
                                    settings.calendar.hiddenCalendarIdentifiers = hidden
                                }
                            ))
                        }
                    }
                }
            }
        }
    }
}
