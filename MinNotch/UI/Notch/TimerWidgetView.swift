import AppKit
import SwiftUI

/// The Timer widget: a countdown, and the Pomodoro cycle built on it.
struct TimerWidgetView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var service: TimerService { environment.timer }

    /// Set from the widget rather than a binding: the field is a scratch value that only
    /// becomes a timer when it is submitted.
    @State private var customMinutes = ""
    @FocusState private var isCustomFocused: Bool

    var viewModel: NotchViewModel?

    /// Sized to the idle state, which is the taller of the two: three rows of options plus
    /// the custom field. The running state is shorter and sits with a little room under it,
    /// which is preferable to the panel resizing every time a timer starts.
    static let preferredHeight: CGFloat = 136

    var body: some View {
        VStack(spacing: 10) {
            if service.isActive {
                running
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.content, value: service.isActive)
    }

    // MARK: Running

    private var running: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: service.phase.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(service.phase.tint)

                Text(service.phase.title)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(.white.opacity(0.8))

                if service.phase.isPomodoro, service.completedIntervals > 0 {
                    Text("· \(service.completedIntervals) done")
                        .font(Typography.helper)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer(minLength: 0)

                if service.state == .finished {
                    Text("Finished")
                        .font(Typography.helper)
                        .foregroundStyle(service.phase.tint)
                }
            }

            Text(service.remainingText)
                .font(.system(size: 38, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)

            // A plain stroked shape, not a `Canvas`: canvas output does not appear in an
            // AppKit layer capture, which is how this project reviews the notch.
            ProgressBar(progress: service.progress, tint: service.phase.tint)
                .frame(height: 4)

            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TimerButton(
                systemImage: service.state == .running ? "pause.fill" : "play.fill",
                help: service.state == .running ? "Pause" : "Resume",
                isEnabled: service.state != .finished
            ) {
                service.toggle()
            }

            TimerButton(systemImage: "forward.end.fill", help: "Skip to the next interval") {
                service.skip()
            }

            TimerButton(systemImage: "stop.fill", help: "Stop and clear") {
                service.reset()
            }

            Chip(label: "+1m", help: "Add a minute") { service.extend(byMinutes: 1) }
            Chip(label: "+5m", help: "Add five minutes") { service.extend(byMinutes: 5) }
        }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Button("Start Pomodoro") { service.startPomodoro() }
                    .buttonStyle(NotchAccentButtonStyle(accent: settings.appearance.resolvedAccent))
                    .help(settings.timer.pomodoroPreset.summary(custom: settings.timer))

                Text(settings.timer.pomodoroPreset.summary(custom: settings.timer))
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            row(title: "Rhythm") {
                // Starting a preset from here runs it without changing the configured one,
                // so trying a different rhythm once is not a settings edit.
                ForEach(PomodoroPreset.allCases) { preset in
                    Chip(
                        label: preset.title,
                        help: preset.summary(custom: settings.timer),
                        isActive: preset == settings.timer.pomodoroPreset
                    ) {
                        service.startPomodoro(preset: preset)
                    }
                }
            }

            row(title: "Countdown") {
                ForEach(Self.quickMinutes, id: \.self) { minutes in
                    Chip(label: "\(minutes)m", help: "Start a \(minutes) minute countdown") {
                        service.startCountdown(minutes: Double(minutes))
                    }
                }
            }

            row(title: "Custom") {
                customField
            }
        }
    }

    /// A labelled row of chips, so the three groups do not read as one undifferentiated wall.
    private func row<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 62, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var customField: some View {
        HStack(spacing: 6) {
            TextField("00", text: $customMinutes)
                .textFieldStyle(.plain)
                .font(Typography.timecode)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 34)
                .focused($isCustomFocused)
                .onSubmit(startCustom)

            Text("min")
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.45))

            Chip(label: "Start", help: "Start a countdown of that many minutes", action: startCustom)
                .disabled(parsedCustomMinutes == nil)
                .opacity(parsedCustomMinutes == nil ? 0.4 : 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isCustomFocused ? 0.14 : 0.08))
        )
        .onTapGesture {
            // The panel is non-activating, so it has to be brought forward before a text
            // field in it can take key events at all.
            NSApp.activate(ignoringOtherApps: true)
            isCustomFocused = true
        }
        // Auto-close would otherwise take the panel away mid-entry.
        .onChange(of: isCustomFocused) { _, focused in
            viewModel?.isInteractionLocked = focused
        }
        .onDisappear { viewModel?.isInteractionLocked = false }
        .animation(Motion.hover, value: isCustomFocused)
    }

    /// Accepts whole and fractional minutes, and nothing else.
    private var parsedCustomMinutes: Double? {
        let trimmed = customMinutes.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0, value <= 1440 else { return nil }
        return value
    }

    private func startCustom() {
        guard let minutes = parsedCustomMinutes else { return }
        service.startCountdown(minutes: minutes)
        customMinutes = ""
        isCustomFocused = false
    }

    private static let quickMinutes = [1, 3, 5, 10, 15, 25, 45, 60]
}

/// A small capsule button, the widget's unit of "one more option".
private struct Chip: View {
    var label: String
    var help: String
    var isActive: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.white.opacity(isActive ? 0.22 : (isHovering ? 0.18 : 0.11)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .animation(Motion.hover, value: isHovering)
    }
}

/// A rounded progress track. Explicit whites, because the notch is black in both appearances.
private struct ProgressBar: View {
    var progress: Double
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, progress)) * proxy.size.width)
            }
        }
    }
}

/// A round transport button for the timer.
///
/// Not `.borderedProminent`: the notch panel is non-activating, so a system prominent style
/// renders in its disabled grey exactly where it matters.
private struct TimerButton: View {
    var systemImage: String
    var help: String
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.3))
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isHovering && isEnabled ? 0.18 : 0.10))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .animation(Motion.hover, value: isHovering)
    }
}
