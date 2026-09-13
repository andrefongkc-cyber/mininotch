import SwiftUI

/// Settings > Timer.
struct TimerSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    /// The three lengths below are the `custom` rhythm. Every other preset supplies its own,
    /// so leaving the sliders live would show numbers the timer was not going to use.
    private var isCustomRhythm: Bool {
        settings.timer.enabled && settings.timer.pomodoroPreset == .custom
    }

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(
            title: "Timer",
            subtitle: "A countdown in the notch, and the Pomodoro cycle built on top of it."
        ) {
            SettingsCard(header: "Timer") {
                SettingsRow(
                    title: "Enable Timer",
                    subtitle: "Adds the Timer tab, and shows a running countdown in the closed pill.",
                    systemImage: "timer"
                ) {
                    SettingsToggle(isOn: $settings.timer.enabled)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Countdown Length",
                    subtitle: "Where a plain countdown starts. The Timer tab also offers a few quick lengths.",
                    systemImage: "clock",
                    isEnabled: settings.timer.enabled
                ) {
                    ValueSlider(
                        value: $settings.timer.defaultCountdownMinutes,
                        range: 1...180,
                        step: 1
                    ) { "\(Int($0)) min" }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Notify on Completion",
                    subtitle: "Post a notification when an interval ends. The first one asks for permission.",
                    systemImage: "bell",
                    isEnabled: settings.timer.enabled
                ) {
                    SettingsToggle(isOn: $settings.timer.notifyOnCompletion)
                }
            }

            SettingsCard(
                header: "Pomodoro",
                footer: "A work interval, then a short break, with a longer one after a full set. The Timer tab can start any of these without changing which one this button uses."
            ) {
                SettingsRow(
                    title: "Rhythm",
                    subtitle: settings.timer.pomodoroPreset.summary(custom: settings.timer),
                    systemImage: "metronome",
                    isEnabled: settings.timer.enabled
                ) {
                    InlinePicker(selection: $settings.timer.pomodoroPreset) {
                        ForEach(PomodoroPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Focus Length",
                    systemImage: "brain.head.profile",
                    isEnabled: isCustomRhythm
                ) {
                    ValueSlider(value: $settings.timer.workMinutes, range: 1...120, step: 1) {
                        "\(Int($0)) min"
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Break Length",
                    systemImage: "cup.and.saucer",
                    isEnabled: isCustomRhythm
                ) {
                    ValueSlider(value: $settings.timer.breakMinutes, range: 1...60, step: 1) {
                        "\(Int($0)) min"
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Long Break Length",
                    systemImage: "figure.walk",
                    isEnabled: isCustomRhythm
                ) {
                    ValueSlider(value: $settings.timer.longBreakMinutes, range: 1...60, step: 1) {
                        "\(Int($0)) min"
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Intervals Before a Long Break",
                    systemImage: "repeat",
                    isEnabled: isCustomRhythm
                ) {
                    ValueSlider(
                        value: Binding(
                            get: { Double(settings.timer.intervalsBeforeLongBreak) },
                            set: { settings.timer.intervalsBeforeLongBreak = Int($0) }
                        ),
                        range: 2...8,
                        step: 1
                    ) { "\(Int($0))" }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Start the Next Interval Automatically",
                    subtitle: "Off means each interval waits for you. On is the point of the technique: it keeps going while you are concentrating.",
                    systemImage: "play.circle",
                    isEnabled: settings.timer.enabled
                ) {
                    SettingsToggle(isOn: $settings.timer.autoAdvance)
                }
            }
        }
    }
}
