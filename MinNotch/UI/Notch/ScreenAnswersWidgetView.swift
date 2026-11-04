import SwiftUI

/// The Answers tab: Read Screen, then the answer to whatever the window in front is asking.
///
/// The panel never takes focus, so the app in front stays in front while it is read: clicking
/// Read Screen reads the window you were working in, not the notch.
struct ScreenAnswersWidgetView: View {
    @Environment(\.notchStyle) private var theme
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    let viewModel: NotchViewModel

    static let preferredHeight: CGFloat = 170
    private static let answerHeight: CGFloat = 128

    private var service: ScreenAnswersService { environment.screenAnswers }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
                .frame(maxWidth: .infinity, minHeight: Self.answerHeight, maxHeight: Self.answerHeight, alignment: .topLeading)
        }
        .onAppear { service.refreshPermission() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(theme.ink.opacity(0.55))
                .lineLimit(1)

            Spacer(minLength: 0)

            // The switches give up their words before anything else gives up room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { gatherToggle(compact: false); watchToggle(compact: false); intervalButton; letterToggle(compact: false) }
                HStack(spacing: 6) { gatherToggle(compact: true); watchToggle(compact: true); intervalButton; letterToggle(compact: true) }
            }

            if service.phase == .answered, !service.answer.isEmpty {
                Button("Copy") { service.copyAnswer() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.ink.opacity(0.7))
                    .help("Copy the answer")
            }

            if service.phase.isBusy {
                Button("Stop") { service.cancel() }
                    .buttonStyle(NotchAccentButtonStyle(accent: theme.accentColor(settings.appearance.resolvedAccent)))
            } else {
                Button {
                    service.ask(on: viewModel.geometry.displayID)
                } label: {
                    if service.isGathering {
                        Label("Answer", systemImage: "checkmark")
                    } else {
                        Label("Read Screen", systemImage: "text.viewfinder")
                    }
                }
                .buttonStyle(NotchAccentButtonStyle(accent: theme.accentColor(settings.appearance.resolvedAccent)))
                .fixedSize()
                .help(service.isGathering ? "Stop gathering and answer the whole page" : "Read the window in front and answer its questions")
            }
        }
    }

    /// Shows the letter of each multiple-choice answer on the left of the closed notch. The same
    /// switch as Settings > Shelf & Notes > Show the Letter in the Notch.
    private func letterToggle(compact: Bool) -> some View {
        @Bindable var settings = settings
        let isOn = settings.advanced.answerLetterInNotch
        return chip("Letter in Notch", symbol: "capsule.lefthalf.filled", isOn: isOn, compact: compact,
                    help: isOn ? "Stop showing the answer's letter in the closed notch" : "Show the answer's letter on the left of the closed notch for 5 seconds") {
            settings.advanced.answerLetterInNotch.toggle()
        }
    }

    /// Scroll and Read: gathers the window while it is scrolled, for a page longer than a screen.
    private func gatherToggle(compact: Bool) -> some View {
        let isOn = service.isGathering
        return chip("Scroll & Read", symbol: "scroll", isOn: isOn, compact: compact,
                    help: isOn ? "Stop gathering and throw away what was gathered" : "Scroll through a long page and MiniNotch reads all of it; then click Answer") {
            if isOn { service.cancelGathering() } else { service.startGathering(on: viewModel.geometry.displayID) }
        }
    }

    /// Keep Reading: the screen is read again every few seconds and answered again when it changes.
    private func watchToggle(compact: Bool) -> some View {
        let isOn = service.isWatching
        return chip("Keep Reading", symbol: "arrow.triangle.2.circlepath", isOn: isOn, compact: compact,
                    help: isOn ? "Stop reading the screen again and again" : "Read the screen again every few seconds, and answer again when it changes") {
            service.setWatching(!isOn, display: viewModel.geometry.displayID)
        }
    }

    /// How often Keep Reading reads: each click steps to the next of 3, 5, 10, 15 and 30 seconds.
    private var intervalButton: some View {
        @Bindable var settings = settings
        let current = settings.advanced.answerReadInterval
        let choices = AdvancedSettings.answerReadIntervals
        return Button {
            let next = choices.first(where: { $0 > current }) ?? choices[0]
            settings.advanced.answerReadInterval = next
        } label: {
            Text("\(Int(current))s")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(theme.ink.opacity(service.isWatching ? 0.8 : 0.45))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(NotchElementView(.button, shape: .capsule, emphasis: 0.04))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("How often Keep Reading reads the screen. Click for the next: 3, 5, 10, 15 or 30 seconds.")
    }

    private func chip(_ title: String, symbol: String, isOn: Bool, compact: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                TransportSymbol.image(symbol, pointSize: 11)
                if !compact {
                    Text(title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isOn ? theme.accentColor(settings.appearance.resolvedAccent) : theme.ink.opacity(0.45))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(NotchElementView(.button, shape: .capsule, emphasis: isOn ? 0.1 : 0.04))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(help)
    }

    private var status: String {
        let app = service.sourceName
        switch service.phase {
        case .idle where service.isGathering:
            let source = app.map { " from \($0)" } ?? ""
            return "Gathering\(source): \(service.gatheredLineCount) lines. Scroll the page, then Answer."
        case .idle, .needsPermission, .failed:
            return "Answers the questions in the window in front, on this Mac"
        case .reading:
            return app.map { "Reading \($0)…" } ?? "Reading the screen…"
        case .thinking:
            return "Answering…"
        case .answered:
            let source = app.map { "From \($0)" } ?? "From the screen"
            return service.isWatching ? source + ", reading every \(Int(settings.advanced.answerReadInterval)) s" : source
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle where service.isGathering:
            message(
                "Scroll slowly through the whole page, top to bottom. MiniNotch reads it as it moves and keeps every new line. Then open the notch and click Answer.",
                symbol: "scroll"
            )
        case .idle:
            message(
                "Open the question in any app, then click Read Screen. MiniNotch reads the window in front and Apple Intelligence answers. Nothing leaves this Mac.",
                symbol: "text.viewfinder"
            )
        case .needsPermission:
            VStack(alignment: .leading, spacing: 8) {
                message(
                    "MiniNotch needs Screen Recording to read the window. Allow it, switch MiniNotch on in System Settings, then reopen MiniNotch.",
                    symbol: "lock"
                )
                Button("Allow…") { service.requestPermission() }
                    .buttonStyle(NotchAccentButtonStyle(accent: theme.accentColor(settings.appearance.resolvedAccent)))
            }
        case .failed(let reason):
            message(reason, symbol: "exclamationmark.triangle")
        case .reading, .thinking, .answered:
            if service.answer.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(service.phase == .reading ? "Reading the text…" : "Thinking…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink.opacity(0.5))
                }
            } else {
                ScrollView {
                    Text(service.answer)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .frame(height: Self.answerHeight)
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink.opacity(0.45))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
