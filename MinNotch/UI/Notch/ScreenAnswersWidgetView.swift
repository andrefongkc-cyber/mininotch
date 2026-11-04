import SwiftUI

/// The Answers tab: five buttons in one row, nothing else (2026-11-03, the user's "make it hella
/// small and just with the 5 buttons"). The answer itself shows as its letter on the closed notch,
/// so the tab no longer draws it; what a button would otherwise have said in a message (a missing
/// permission, a failure) is its label or its tooltip.
///
/// The panel never takes focus, so the app in front stays in front while it is read: clicking
/// Read Screen reads the window you were working in, not the notch.
struct ScreenAnswersWidgetView: View {
    @Environment(\.notchStyle) private var theme
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings
    let viewModel: NotchViewModel

    static let preferredHeight: CGFloat = 30
    /// The row of five symbols, for the panel's width on this tab (`NotchViewModel.expandedPanelWidth`).
    static let rowWidth: CGFloat = 184

    private var service: ScreenAnswersService { environment.screenAnswers }

    var body: some View {
        // Symbols only (2026-11-03, "just be all symbols"); each says what it is in its tooltip.
        HStack(spacing: 6) {
            gatherToggle(compact: true)
            watchToggle(compact: true)
            intervalButton
            letterToggle(compact: true)
            mainButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { service.refreshPermission() }
    }

    /// Read Screen; Answer while gathering; Stop while busy; Allow… without the permission.
    @ViewBuilder
    private var mainButton: some View {
        let style = NotchAccentButtonStyle(accent: theme.accentColor(settings.appearance.resolvedAccent))
        if service.phase.isBusy {
            Button {
                service.cancel()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(style)
            .fixedSize()
            .help(service.phase == .reading ? "Reading the screen. Click to stop." : "Answering. Click to stop.")
        } else if service.phase == .needsPermission {
            Button { service.requestPermission() } label: { Image(systemName: "lock") }
                .buttonStyle(style)
                .fixedSize()
                .help("Allow… MiniNotch needs Screen Recording to read the window. Allow it, switch MiniNotch on in System Settings, then reopen MiniNotch.")
        } else {
            Button {
                service.ask(on: viewModel.geometry.displayID)
            } label: {
                if service.isGathering {
                    Image(systemName: "checkmark")
                } else if case .failed = service.phase {
                    Image(systemName: "exclamationmark.triangle")
                } else {
                    Image(systemName: "text.viewfinder")
                }
            }
            .buttonStyle(style)
            .fixedSize()
            .help(mainHelp)
        }
    }

    private var mainHelp: String {
        if service.isGathering {
            return "Answer: gathered \(service.gatheredLineCount) lines. Stop gathering and answer the whole page."
        }
        if case .failed(let reason) = service.phase { return "Read Screen. Last time: " + reason }
        return "Read Screen: read the window in front and answer its questions. Nothing leaves this Mac."
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
}
