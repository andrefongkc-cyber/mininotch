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
                    Label("Read Screen", systemImage: "text.viewfinder")
                }
                .buttonStyle(NotchAccentButtonStyle(accent: theme.accentColor(settings.appearance.resolvedAccent)))
                .help("Read the window in front and answer its questions")
            }
        }
    }

    private var status: String {
        let app = service.sourceName
        switch service.phase {
        case .idle, .needsPermission, .failed:
            return "Answers the questions in the window in front, on this Mac"
        case .reading:
            return app.map { "Reading \($0)…" } ?? "Reading the screen…"
        case .thinking:
            return "Answering…"
        case .answered:
            return app.map { "From \($0)" } ?? "From the screen"
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch service.phase {
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
