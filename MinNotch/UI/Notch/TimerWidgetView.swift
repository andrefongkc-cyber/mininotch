import AppKit
import SwiftUI

/// The Timer widget: a countdown and the Pomodoro cycle built on it, or a stopwatch.
///
/// Every state has the same header: the Timer | Stopwatch switch on the left, and Focus and the
/// pop-out button on the right. Under it, idle, are two rows, Pomodoro (choose a rhythm, then
/// Start) and Countdown (a quick length starts at once, or type one). It used to be one crowded
/// top row of Start Pomodoro, Focus Timer, a cut-off summary and the switch, over three labelled
/// rows, and the user called it messy. The same view fills the pop-out window
/// (`FloatingTimerController`), which is why the choices live in `AppEnvironment.stopwatch`.
struct TimerWidgetView: View {
    @Environment(\.notchStyle) private var theme
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    private var service: TimerService { environment.timer }
    private var stopwatch: Stopwatch { environment.stopwatch }

    /// Set from the widget rather than a binding: the field is a scratch value that only
    /// becomes a timer when it is submitted.
    @State private var customMinutes = ""
    @FocusState private var isCustomFocused: Bool

    var viewModel: NotchViewModel?
    /// In the pop-out window, which has no pop-out button of its own.
    var isFloating = false

    /// The tallest state, a running timer: header, status line, time, bar, controls.
    nonisolated static let preferredHeight: CGFloat = 140

    private static let labelWidth: CGFloat = 70

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            Group {
                if stopwatch.mode == .stopwatch {
                    stopwatchBody
                } else if service.isActive {
                    runningBody
                } else {
                    idleBody
                }
            }
            // Centred in the pop-out window, so a large one does not leave the idle rows at the
            // top over an empty half; the running states fill it either way.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isFloating ? .center : .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.content, value: service.isActive)
        .animation(Motion.content, value: stopwatch.mode)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            ModePicker(mode: Binding(get: { stopwatch.mode }, set: { stopwatch.mode = $0 }))

            Spacer(minLength: 8)

            Chip(
                label: "Focus",
                systemImage: "scope",
                help: "Focus: pop the timer out when it starts, and start it over if you switch to another app",
                isActive: settings.timer.focusMode
            ) {
                settings.timer.focusMode.toggle()
            }

            if !isFloating {
                TimerButton(
                    systemImage: stopwatch.isPoppedOut ? "pip.exit" : "pip.enter",
                    help: stopwatch.isPoppedOut ? "Put the timer back in the notch" : "Pop the timer out into its own window"
                ) {
                    stopwatch.isPoppedOut.toggle()
                    environment.floatingTimer.sync()
                }
            }
        }
    }

    // MARK: Idle

    private var idleBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                pomodoroRow(labelled: true)
                pomodoroRow(labelled: false)
            }

            ViewThatFits(in: .horizontal) {
                countdownRow([1, 3, 5, 10, 15, 25, 45, 60])
                countdownRow([1, 5, 10, 15, 30, 60])
                countdownRow([5, 15, 30])
            }
        }
    }

    /// The rhythms choose what Start runs, and only that: a chip that also started it left no way
    /// to choose one without starting (the user's report).
    private func pomodoroRow(labelled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            pomodoroChips(labelled: labelled)
            Text(settings.timer.pomodoroPreset.summary(custom: settings.timer))
                .font(Typography.helper)
                .foregroundStyle(theme.ink.opacity(0.4))
                .lineLimit(1)
                .padding(.leading, labelled ? Self.labelWidth + 6 : 0)
        }
    }

    private func pomodoroChips(labelled: Bool) -> some View {
        HStack(spacing: 6) {
            if labelled { rowLabel("Pomodoro") }
            ForEach(PomodoroPreset.allCases) { preset in
                Chip(
                    label: preset.title,
                    help: preset.summary(custom: settings.timer),
                    isActive: preset == settings.timer.pomodoroPreset
                ) {
                    settings.timer.pomodoroPreset = preset
                }
            }
            Spacer(minLength: 6)
            Button {
                service.startPomodoro()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .lineLimit(1)
            }
            .buttonStyle(NotchAccentButtonStyle(accent: settings.appearance.resolvedAccent))
            .fixedSize()
            .help("Start a Pomodoro set: \(settings.timer.pomodoroPreset.summary(custom: settings.timer))")
        }
    }

    /// A quick length starts at once; the field at the end takes any other.
    private func countdownRow(_ minutes: [Int]) -> some View {
        HStack(spacing: 6) {
            rowLabel("Countdown")
            ForEach(minutes, id: \.self) { length in
                Chip(label: "\(length)m", help: "Start a \(length) minute countdown") {
                    service.startCountdown(minutes: Double(length))
                }
            }
            Spacer(minLength: 6)
            customField
        }
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(Typography.helper)
            .foregroundStyle(theme.ink.opacity(0.4))
            .frame(width: Self.labelWidth, alignment: .leading)
    }

    private var customField: some View {
        HStack(spacing: 4) {
            TextField("00", text: $customMinutes)
                .textFieldStyle(.plain)
                .font(Typography.timecode)
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .frame(width: 26)
                .focused($isCustomFocused)
                .onSubmit(startCustom)

            Text("min")
                .font(Typography.helper)
                .foregroundStyle(theme.ink.opacity(0.45))

            Button(action: startCustom) {
                TransportSymbol.image("play.fill", pointSize: 9)
                    .foregroundStyle(theme.ink.opacity(parsedCustomMinutes == nil ? 0.3 : 0.9))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(parsedCustomMinutes == nil)
            .help("Start a countdown of that many minutes")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(
            NotchElementView(.tile, shape: .capsule, emphasis: isCustomFocused ? 0.14 : 0.08)
        )
        .fixedSize()
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

    // MARK: Running

    private var runningBody: some View {
        VStack(spacing: 6) {
            statusLine {
                TransportSymbol.image(service.phase.symbolName, pointSize: 10)
                    .foregroundStyle(service.phase.tint)
                Text(service.phase.title)
                    .foregroundStyle(theme.ink.opacity(0.75))
                if service.phase.isPomodoro, service.completedIntervals > 0 {
                    Text("· \(service.completedIntervals) done")
                }
                if service.state == .finished {
                    Text("· Finished").foregroundStyle(service.phase.tint)
                }
            }

            BigTime(text: service.remainingText, fills: isFloating)

            // A plain stroked shape, not a `Canvas`: canvas output does not appear in an
            // AppKit layer capture, which is how this project reviews the notch.
            ProgressBar(progress: service.progress, tint: service.phase.tint)
                .frame(height: 4)

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
    }

    // MARK: Stopwatch

    private var stopwatchBody: some View {
        VStack(spacing: 6) {
            statusLine {
                TransportSymbol.image("stopwatch", pointSize: 10)
                    .foregroundStyle(settings.appearance.resolvedAccent)
                if let latest = stopwatch.laps.first {
                    // The lap's own length, not the running total.
                    let split = latest - (stopwatch.laps.count > 1 ? stopwatch.laps[1] : 0)
                    Text("Lap \(stopwatch.laps.count)  \(Stopwatch.format(split))")
                        .monospacedDigit()
                } else {
                    Text(stopwatch.hasTime ? "Stopwatch" : "Stopwatch · Lap marks a split")
                }
            }

            // Redraws only while running: every frame to the hundredth, or ten times a second to
            // the tenth in Low Power Mode or on a low battery.
            let precision = Stopwatch.Precision(savingPower: environment.battery.status.savesPower)
            TimelineView(.animation(minimumInterval: precision.redrawInterval, paused: !stopwatch.isRunning)) { context in
                BigTime(
                    text: Stopwatch.format(stopwatch.elapsed(at: context.date), precision: precision),
                    fills: isFloating
                )
            }

            HStack(spacing: 8) {
                TimerButton(
                    systemImage: stopwatch.isRunning ? "pause.fill" : "play.fill",
                    help: stopwatch.isRunning ? "Pause" : (stopwatch.hasTime ? "Resume" : "Start")
                ) { stopwatch.toggle() }
                TimerButton(systemImage: "flag.fill", help: "Lap", isEnabled: stopwatch.isRunning) {
                    stopwatch.lap()
                }
                TimerButton(systemImage: "arrow.counterclockwise", help: "Reset", isEnabled: stopwatch.hasTime) {
                    stopwatch.reset()
                }
            }
        }
    }

    // MARK: Status

    /// One centred line above the big number: what is running, then what Focus is holding it to.
    private func statusLine<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) {
            content()
            focusStatus
        }
        .font(Typography.helper)
        .foregroundStyle(theme.ink.opacity(0.45))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    /// What Focus is holding the timer or stopwatch to, and where the user went the last time it
    /// started over.
    @ViewBuilder
    private var focusStatus: some View {
        let focus = environment.focusGuard
        if focus.isArmed, let app = focus.focusAppName {
            if let left = focus.lastLeftTo {
                Text("· Restarted: you went to \(left). Stay in \(app)")
                    .foregroundStyle(Color(nsColor: .systemRed))
            } else {
                Text("· Stay in \(app)")
            }
        }
    }
}

/// The time, large. 38 points in the notch; in the pop-out window it fills whatever room the
/// rest leaves, so expanding or resizing the window makes the number bigger.
private struct BigTime: View {
    @Environment(\.notchStyle) private var theme
    var text: String
    var fills: Bool

    private static let notchSize: CGFloat = 38

    var body: some View {
        if fills {
            GeometryReader { proxy in
                Text(text)
                    .font(Self.font(size: Self.size(fitting: text, in: proxy.size)))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(minHeight: 40)
        } else {
            Text(text)
                .font(Self.font(size: Self.notchSize))
                .foregroundStyle(theme.ink)
        }
    }

    private static func font(size: CGFloat) -> Font {
        .system(size: size, weight: .medium).monospacedDigit()
    }

    /// The largest size the text fits at, judged with every digit a 0, so the size holds still
    /// while the digits change and only moves when the time gains a digit.
    private static func size(fitting text: String, in space: CGSize) -> CGFloat {
        let template = String(text.map { $0.isNumber ? "0" : $0 })
        let reference = NSFont.monospacedDigitSystemFont(ofSize: 100, weight: .medium)
        let width = (template as NSString).size(withAttributes: [.font: reference]).width
        let height = reference.ascender - reference.descender + reference.leading
        guard width > 0, height > 0 else { return notchSize }
        // A little short of the width, so a large number does not run edge to edge.
        return max(12, floor(min(space.width * 0.92 / width, space.height / height) * 100))
    }
}

/// Timer or Stopwatch, as one switch.
private struct ModePicker: View {
    @Environment(\.notchStyle) private var theme
    @Binding var mode: Stopwatch.Mode

    var body: some View {
        HStack(spacing: 2) {
            segment(.timer, title: "Timer", symbol: "timer")
            segment(.stopwatch, title: "Stopwatch", symbol: "stopwatch")
        }
        .padding(2)
        .background(NotchElementView(.tile, shape: .capsule, emphasis: 0.08))
        .fixedSize()
    }

    private func segment(_ value: Stopwatch.Mode, title: String, symbol: String) -> some View {
        let selected = mode == value
        return Button {
            mode = value
        } label: {
            HStack(spacing: 4) {
                TransportSymbol.image(symbol, pointSize: 10)
                Text(title)
            }
            .font(selected ? Typography.helper.weight(.semibold) : Typography.helper)
            .foregroundStyle(theme.ink.opacity(selected ? 1 : 0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background {
                if selected {
                    NotchElementView(.button, shape: .capsule, emphasis: 0.2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(Motion.hover, value: selected)
    }
}

/// A small capsule button, the widget's unit of "one more option".
private struct Chip: View {
    @Environment(\.notchStyle) private var theme
    @Environment(SettingsStore.self) private var settings
    var label: String
    var systemImage: String? = nil
    var help: String
    var isActive: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            // On reads in the accent, bolder: the fill alone, 0.22 against 0.11, left an
            // on chip and an off one looking the same (Focus Timer, Timer or Stopwatch).
            HStack(spacing: 4) {
                if let systemImage {
                    TransportSymbol.image(systemImage, pointSize: 10)
                }
                Text(label)
            }
                .font(isActive ? Typography.helper.weight(.semibold) : Typography.helper)
                .foregroundStyle(isActive ? settings.appearance.resolvedAccent : theme.ink.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    // Raised at rest and pressed in when chosen, in a style with depth; Minimal fills both.
                    NotchElementView(isActive ? .button : .tile, shape: .capsule, emphasis: isActive ? 0.22 : (isHovering ? 0.18 : 0.11))
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
    @Environment(\.notchStyle) private var theme
    var progress: Double
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                NotchElementView(.groove, shape: .capsule, emphasis: 0.14)
                NotchTrackFill(color: tint)
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
    @Environment(\.notchStyle) private var theme
    var systemImage: String
    var help: String
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            TransportSymbol.image(systemImage, pointSize: 12)
                .foregroundStyle(theme.ink.opacity(isEnabled ? 0.9 : 0.3))
                .frame(width: 30, height: 24)
                .background(
                    NotchElementView(.button, shape: .rounded(7), emphasis: isHovering && isEnabled ? 0.18 : 0.10)
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
