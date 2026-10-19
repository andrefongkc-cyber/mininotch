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

            // The clock style, in the notch and the pop-out alike: it was the pop-out's alone, and
            // the user wanted to choose it, and see it, in the notch too.
            TimerButton(systemImage: settings.timer.clockStyle.symbolName, help: "Clock style: \(settings.timer.clockStyle.title)") {
                // In the notch, drawn in the panel; in the pop-out window (no view model), AppKit's.
                NotchMenu.show(TimerClockStyle.allCases.map { style in
                    NotchMenu.Item(title: style.title, symbol: style.symbolName,
                                   isOn: style == settings.timer.clockStyle) {
                        settings.timer.clockStyle = style
                    }
                }, anchor: "clockStyle", in: viewModel)
            }
            .notchMenuAnchor("clockStyle", in: viewModel)

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

            BigTime(text: service.remainingText, fills: isFloating, style: clockStyle)

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

    /// The stopwatch, and once there is a lap, every lap in a column beside it: the one being run
    /// now, ticking, then the rest newest first, fastest in green and slowest in red. It used to
    /// show only the latest lap, in the line above the time, with the panel's sides empty (the
    /// user's report). Where the column does not fit, that line is still what shows.
    private var stopwatchBody: some View {
        let precision = Stopwatch.Precision(
            showsFraction: settings.timer.stopwatchShowsFraction,
            savingPower: environment.battery.status.savesPower
        )
        return Group {
            if stopwatch.laps.isEmpty {
                stopwatchMain(precision, latestLapInStatus: false)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        stopwatchMain(precision, latestLapInStatus: false)
                            .frame(minWidth: Self.stopwatchMinWidth, maxWidth: .infinity)
                        Rectangle()
                            .fill(theme.ink.opacity(0.08))
                            .frame(width: 1, height: isFloating ? nil : Self.lapsHeight)
                        lapsList(precision)
                            .frame(width: Self.lapsWidth)
                    }
                    stopwatchMain(precision, latestLapInStatus: true)
                }
            }
        }
    }

    private static let stopwatchMinWidth: CGFloat = 230
    private static let lapsWidth: CGFloat = 170
    /// The room under the header in the notch, which a `ScrollView` has to be told: it has no
    /// height of its own.
    private static let lapsHeight: CGFloat = 96

    private func stopwatchMain(_ precision: Stopwatch.Precision, latestLapInStatus: Bool) -> some View {
        VStack(spacing: 6) {
            statusLine {
                TransportSymbol.image("stopwatch", pointSize: 10)
                    .foregroundStyle(settings.appearance.resolvedAccent)
                if latestLapInStatus, let latest = stopwatch.laps.first {
                    // The lap's own length, not the running total.
                    let split = latest - (stopwatch.laps.count > 1 ? stopwatch.laps[1] : 0)
                    Text("Lap \(stopwatch.laps.count)  \(Stopwatch.format(split, precision: lapPrecision))")
                        .monospacedDigit()
                } else if stopwatch.laps.isEmpty {
                    Text(stopwatch.hasTime ? "Stopwatch" : "Stopwatch · Lap marks a split")
                } else {
                    Text("Stopwatch")
                }
            }

            ticking(from: 0, precision) { elapsed in
                BigTime(
                    text: Stopwatch.format(elapsed, precision: precision),
                    fills: isFloating,
                    style: clockStyle
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
                Chip(
                    label: ".00",
                    help: settings.timer.stopwatchShowsFraction ? "Hide hundredths of a second" : "Show hundredths of a second",
                    isActive: settings.timer.stopwatchShowsFraction
                ) {
                    settings.timer.stopwatchShowsFraction.toggle()
                }
            }
        }
    }

    /// Finished laps are still, so they show hundredths whenever the hundredths are on.
    private var lapPrecision: Stopwatch.Precision {
        settings.timer.stopwatchShowsFraction ? .hundredths : .seconds
    }

    private func lapsList(_ precision: Stopwatch.Precision) -> some View {
        let laps = stopwatch.laps
        // Each lap's own length, newest first, from the totals the stopwatch keeps.
        let splits = laps.indices.map { laps[$0] - (laps.indices.contains($0 + 1) ? laps[$0 + 1] : 0) }
        // Fastest and slowest only mean something once there are three to compare.
        let marks = splits.count >= 3
        let fastest = splits.min()
        let slowest = splits.max()
        return ScrollView(.vertical) {
            VStack(spacing: 4) {
                // The lap being run now, ticking with the big number.
                ticking(from: laps.first ?? 0, precision) { current in
                    lapRow(laps.count + 1, Stopwatch.format(current, precision: precision),
                           tint: settings.appearance.resolvedAccent)
                }
                ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                    lapRow(laps.count - index, Stopwatch.format(split, precision: lapPrecision), tint: {
                        if marks, split == fastest { return Color(nsColor: .systemGreen) }
                        if marks, split == slowest { return Color(nsColor: .systemRed) }
                        return theme.ink.opacity(0.85)
                    }())
                    .help("Lap \(laps.count - index): \(Stopwatch.format(split, precision: lapPrecision)), at \(Stopwatch.format(laps[index], precision: lapPrecision))")
                }
            }
            .padding(.trailing, 4)
        }
        .scrollIndicators(.automatic)
        // Faded at the foot, so a row cut short there reads as more to scroll to.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                     .init(color: .black.opacity(0), location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .frame(height: isFloating ? nil : Self.lapsHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func lapRow(_ number: Int, _ time: String, tint: Color) -> some View {
        HStack {
            Text("Lap \(number)")
                .foregroundStyle(theme.ink.opacity(0.45))
            Spacer(minLength: 8)
            Text(time)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .font(Typography.helper)
        .lineLimit(1)
    }

    /// Redraws only while running: every frame to the hundredth; ten times a second to the tenth
    /// in Low Power Mode or on a low battery; once a second with the hundredths off. The slower
    /// two land on the stopwatch's own grid (`zeroDate`, plus `offset` for a lap that started
    /// there), so each redraw is the moment a digit turns over rather than up to a period after it.
    /// `content` gets the time since `offset`.
    @ViewBuilder
    private func ticking<Content: View>(
        from offset: TimeInterval, _ precision: Stopwatch.Precision,
        @ViewBuilder content: @escaping (TimeInterval) -> Content
    ) -> some View {
        if let zero = stopwatch.zeroDate {
            if let period = precision.redrawPeriod {
                TimelineView(.periodic(from: zero.addingTimeInterval(offset), by: period)) { context in
                    // A hair past the grid, so a value that lands exactly on a tenth is not
                    // rounded down to the one before.
                    content(stopwatch.elapsed(at: context.date.addingTimeInterval(0.001)) - offset)
                }
            } else {
                TimelineView(.animation) { context in
                    content(stopwatch.elapsed(at: context.date) - offset)
                }
            }
        } else {
            content(stopwatch.elapsed() - offset)
        }
    }

    private var clockStyle: TimerClockStyle { settings.timer.clockStyle }

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

/// The time, large. 38 points in the notch, or a clock style in a band `styledNotchHeight` tall;
/// in the pop-out window it fills whatever room the rest leaves, so expanding or resizing the
/// window makes the number bigger.
private struct BigTime: View {
    @Environment(\.notchStyle) private var theme
    var text: String
    var fills: Bool
    var style: TimerClockStyle = .plain

    private static let notchSize: CGFloat = 38
    /// A little taller than the plain number's line, since a styled one draws cards or a plate
    /// around its digits; the tab's height has room for it.
    private static let styledNotchHeight: CGFloat = 50

    var body: some View {
        if style != .plain {
            GeometryReader { proxy in
                ClockFaceView(text: text, style: style, space: proxy.size)
            }
            .frame(minHeight: fills ? 40 : Self.styledNotchHeight, maxHeight: fills ? .infinity : Self.styledNotchHeight)
        } else if fills {
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
