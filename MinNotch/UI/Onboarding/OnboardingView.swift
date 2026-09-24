import CoreLocation
import EventKit
import SwiftUI

/// State for one run of the first-launch tutorial.
@Observable
@MainActor
final class OnboardingModel {
    enum Page: Int, CaseIterable, Identifiable {
        case welcome
        case features
        case howTo
        case permissions
        case done

        var id: Int { rawValue }
    }

    var page: Page
    /// What is ticked. Nothing is written to settings until the checklist is confirmed.
    var selection: Set<OnboardingFeature>
    /// The preset the selection still matches, or nil once the user has changed a box.
    private(set) var preset: OnboardingPreset?

    init(page: Page = .welcome, selection: Set<OnboardingFeature>, preset: OnboardingPreset?) {
        self.page = page
        self.selection = selection
        self.preset = preset
    }

    func choose(_ preset: OnboardingPreset) {
        selection = preset.features
        self.preset = preset
    }

    func toggle(_ feature: OnboardingFeature) {
        if selection.contains(feature) {
            selection.remove(feature)
        } else {
            selection.insert(feature)
        }
        preset = OnboardingPreset.allCases.first { $0.features == selection }
    }

    /// Writes the checklist to settings. Every available feature is written, ticked or not,
    /// so the result is exactly what was on screen and not that merged with the defaults.
    func apply(to settings: SettingsStore) {
        // Safe to run again after going back and changing a box: it rewrites every feature,
        // so the second answer replaces the first rather than merging with it.
        for feature in OnboardingFeature.available {
            feature.apply(selection.contains(feature), to: settings)
        }
    }
}

/// The first-launch tutorial: what MinNotch is, what to switch on, how to use it, and what it
/// will ask for.
///
/// Drawn in plain colours rather than materials, so `--capture-onboarding` can read every page
/// back from a real window. The Settings window uses materials and cannot be captured at all,
/// which is exactly the situation this avoids repeating.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    var onSkip: () -> Void
    var onFinish: (_ openSettings: Bool) -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    static let size = CGSize(width: 680, height: 580)

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case .welcome: WelcomePage()
                case .features: FeaturesPage(model: model)
                case .howTo: HowToPage()
                case .permissions: PermissionsPage(selection: model.selection)
                case .done: DonePage(featureCount: model.selection.count)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 36)
            .padding(.top, 26)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.paneBackground)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.page != .done {
                Button("Skip Setup", action: onSkip)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.secondaryText)
                    .help("Keep the defaults. Everything here is also in Settings.")
            }

            Spacer(minLength: 0)

            if model.page != .welcome && model.page != .done {
                Button("Back") { move(by: -1) }
                    .controlSize(.large)
            }

            primaryButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        // Overlaid rather than placed between the buttons, so the dots stay centred on the
        // window whether Skip is showing or not. Placed in the row they slid left on the last
        // page. Left out on that page entirely: its two buttons reach the middle, and at the
        // end of the tour there is no position left to show.
        .overlay { if model.page != .done { pageDots } }
        .background(
            Palette.cardBackground
                .overlay(alignment: .top) { Divider().overlay(Palette.separator) }
        )
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.page {
        case .welcome:
            Button("Get Started") { move(by: 1) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        case .features:
            Button(model.selection.isEmpty ? "Continue With Nothing On" : "Continue") {
                model.apply(to: settings)
                move(by: 1)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        case .howTo, .permissions:
            Button("Continue") { move(by: 1) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        case .done:
            HStack(spacing: 10) {
                Button("Open Settings") { onFinish(true) }
                    .controlSize(.large)
                Button("Start Using MinNotch") { onFinish(false) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Page.allCases) { page in
                Circle()
                    .fill(page == model.page ? Palette.controlAccent : Palette.separator)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(model.page.rawValue + 1) of \(OnboardingModel.Page.allCases.count)")
    }

    private func move(by offset: Int) {
        guard let next = OnboardingModel.Page(rawValue: model.page.rawValue + offset) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { model.page = next }
    }
}

// MARK: - Shared pieces

private struct PageHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Palette.primaryText)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TintedIcon: View {
    var symbolName: String
    var tint: Color
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Welcome

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            illustration

            VStack(spacing: 8) {
                Text("Welcome to MinNotch")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.primaryText)

                Text("The notch becomes somewhere useful. Hover over it or click it, and it opens into a panel with what's playing, your calendar, a timer and more. Move away and it tucks back behind the camera.")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
            }

            Text("This takes about a minute. Skip whenever you like; everything here is also in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The idea in one picture: a closed notch, and the same notch opened.
    private var illustration: some View {
        HStack(spacing: 26) {
            screen(caption: "Closed") {
                NotchShape(shoulderRadius: 5, bottomRadius: 8)
                    .fill(Color.black)
                    .frame(width: 70, height: 18)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)

            screen(caption: "Open") {
                ZStack(alignment: .top) {
                    NotchShape(shoulderRadius: 5, bottomRadius: 12)
                        .fill(Color.black)
                        .frame(width: 170, height: 80)

                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(Color.white.opacity(0.85)).frame(width: 70, height: 5)
                            Capsule().fill(Color.white.opacity(0.4)).frame(width: 48, height: 4)
                            Capsule().fill(Color.white.opacity(0.18)).frame(width: 90, height: 3)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.accentColor).frame(width: 36, height: 3)
                                }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 26)
                }
            }
        }
    }

    private func screen<Content: View>(caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.93, green: 0.45, blue: 0.42), Color(red: 0.36, green: 0.29, blue: 0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                content()
            }
            .frame(width: 210, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
        }
    }
}

// MARK: - Features

private struct FeaturesPage: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: "Pick what you want",
                subtitle: "What most people like is already switched on. Tick or untick anything; each one says what it does and anything worth knowing first."
            )

            HStack(spacing: 10) {
                Picker("Start from", selection: Binding(
                    get: { model.preset },
                    set: { if let preset = $0 { model.choose(preset) } }
                )) {
                    ForEach(OnboardingPreset.allCases) { preset in
                        Text(preset.title).tag(Optional(preset))
                    }
                    if model.preset == nil {
                        Text("Custom").tag(OnboardingPreset?.none)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer(minLength: 0)

                Text("\(model.selection.count) of \(OnboardingFeature.available.count) on")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(OnboardingFeature.Group.allCases) { group in
                        let features = OnboardingFeature.available.filter { $0.group == group }
                        if !features.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.tertiaryText)
                                    .padding(.leading, 4)

                                VStack(spacing: 6) {
                                    ForEach(features) { feature in
                                        FeatureRow(
                                            feature: feature,
                                            isOn: model.selection.contains(feature)
                                        ) {
                                            model.toggle(feature)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
        }
    }
}

/// One tickable feature. The whole card is the target, not just the checkmark, because the
/// card is what someone reading the description is already looking at.
private struct FeatureRow: View {
    let feature: OnboardingFeature
    let isOn: Bool
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                TintedIcon(symbolName: feature.symbolName, tint: feature.tint, size: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(feature.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.primaryText)
                        if let badge = feature.badge { BadgeView(badge) }
                    }
                    Text(feature.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caveat = feature.caveat {
                        Label(caveat, systemImage: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.tertiaryText)
                            .labelStyle(.titleAndIcon)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? Palette.controlAccent : Palette.tertiaryText)
                    .padding(.top, 3)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isOn ? Palette.controlAccent.opacity(0.55) : Palette.separator.opacity(isHovering ? 1 : 0.6),
                        lineWidth: isOn ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - How to

private struct HowToPage: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Getting around",
                subtitle: "Five things that are not obvious the first time."
            )

            VStack(alignment: .leading, spacing: 16) {
                tip("cursorarrow.rays", .systemBlue,
                    "Hover over the notch, or click it",
                    "It waits a moment before opening, so sweeping the pointer across the menu bar will not set it off.")
                tip("keyboard", .systemIndigo,
                    "\(shortcut) opens and closes it from anywhere",
                    "Change the shortcut in Settings › Shortcuts.")
                tip("gearshape", .systemGray,
                    "Settings are one click away",
                    "Click the gear in the open notch or the MinNotch icon in the menu bar. In Settings, press ⌘F to search for anything.")
                tip("hand.draw", .systemTeal,
                    "Arrange it your way",
                    "Drag what shows beside the notch, the play controls, and the top bar's tabs into the order you like, in General and Appearance.")
                tip("cursorarrow.click.2", .systemPink,
                    "Right-click for more",
                    "The effects button on Now Playing has glow styles and a choice of where the light shows.")
            }
        }
    }

    private var shortcut: String {
        settings.shortcuts.combo(for: .toggleNotch)?.displayString ?? "A keyboard shortcut"
    }

    private func tip(_ symbol: String, _ tint: NSColor, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            TintedIcon(symbolName: symbol, tint: Color(nsColor: tint), size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsPage: View {
    let selection: Set<OnboardingFeature>

    @Environment(AppEnvironment.self) private var environment
    @State private var notificationsAnswered: Bool?
    @State private var isAccessibilityTrusted = SystemKeyInterceptor.isTrusted
    @State private var audioAllowed = false
    @State private var audioAsked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: "What MinNotch can ask for",
                subtitle: "Nothing has been asked for yet. Every permission is here, whatever you switched on, so you can allow them now while you know why. Anything you skip is asked for the first time a feature needs it."
            )

            // Every permission, not only those for what was ticked. Someone who turns a feature
            // on later from Settings should have seen what it asks for here first, and the two
            // that need a trip to System Settings otherwise, Accessibility and system audio, are
            // the ones worth allowing while the reason is on screen.
            VStack(spacing: 7) {
                permission(
                    symbol: "calendar", tint: .systemOrange,
                    title: "Calendar and Reminders",
                    detail: "To show your events and reminders in the notch."
                ) { calendarAction }

                permission(
                    symbol: "accessibility", tint: .systemBlue,
                    title: "Accessibility",
                    detail: "To hide Apple's volume and brightness overlay so only MinNotch's shows. Used by HUDs > Hide the System Overlay."
                ) { accessibilityAction }

                permission(
                    symbol: "waveform", tint: .systemPurple,
                    title: "System Audio",
                    detail: "To hear what is playing, so the glow follows the beat and lyrics line up with the singing. Nothing is recorded or kept."
                ) { audioAction }

                permission(
                    symbol: "location.fill", tint: .systemCyan,
                    title: "Location",
                    detail: "For the weather where you are, rounded to about a kilometre. Or type a city in Settings > Weather and skip this."
                ) { locationAction }

                permission(
                    symbol: "bell.badge", tint: .systemRed,
                    title: "Notifications",
                    detail: "To tell you when a timer or focus session ends, and when the battery is low."
                ) { notificationsAction }

                permission(
                    symbol: "music.note", tint: .systemPink,
                    title: "Controlling Music and Spotify",
                    detail: "macOS asks the first time one of them plays. MinNotch never opens either app itself."
                ) {
                    Text("Asked when needed")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }

            // Part of this line rather than a card of its own: it is not a permission, and a
            // seventh card does not fit the window.
            Label(privacyLine, systemImage: "lock")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Accessibility is granted in System Settings with no callback, so look again while
        // this page is showing.
        .task {
            while !Task.isCancelled {
                isAccessibilityTrusted = SystemKeyInterceptor.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear { audioAllowed = environment.audioAnalyzer.isRunning }
        .onChange(of: environment.audioAnalyzer.isRunning) { _, isRunning in
            guard isRunning, audioAsked else { return }
            audioAllowed = true
            // Allowed now; keep listening only if a setting actually wants it.
            environment.reconcileAudioAnalysis()
        }
    }

    private var privacyLine: String {
        guard selection.contains(.onlineLyrics) else {
            return "Everything else stays on your Mac. No accounts, no analytics, nothing uploaded."
        }
        return "Synced Lyrics sends the track's title, artist, album and length to lrclib.net. Everything else stays on your Mac."
    }

    @ViewBuilder
    private var calendarAction: some View {
        switch environment.calendarService.authorizationStatus {
        case .fullAccess, .authorized:
            granted
        case .denied, .restricted, .writeOnly:
            changeInSettings
        default:
            Button("Allow Now") { environment.calendarService.requestAccess() }
        }
    }

    @ViewBuilder
    private var accessibilityAction: some View {
        if isAccessibilityTrusted {
            granted
        } else {
            Button("Allow Now") { SystemKeyInterceptor.requestTrust() }
                .help("macOS shows its own dialog, which opens Privacy & Security > Accessibility")
        }
    }

    @ViewBuilder
    private var audioAction: some View {
        if audioAllowed {
            granted
        } else if audioAsked, environment.audioAnalyzer.failure != nil {
            changeInSettings
                .help("Privacy & Security > Screen & System Audio Recording")
        } else if environment.audioAnalyzer.isStarting {
            ProgressView().controlSize(.small)
        } else {
            Button("Allow Now") {
                audioAsked = true
                environment.requestSystemAudioAccess()
            }
        }
    }

    @ViewBuilder
    private var locationAction: some View {
        switch environment.weather.locationAuthorization {
        case .notDetermined:
            Button("Allow Now") { environment.weather.requestLocationAccess() }
        case .denied, .restricted:
            changeInSettings
        default:
            granted
        }
    }

    @ViewBuilder
    private var notificationsAction: some View {
        switch notificationsAnswered {
        case .some(true):
            granted
        case .some(false):
            changeInSettings
        case .none:
            Button("Allow Now") {
                NotificationCenterBridge.requestAuthorizationIfNeeded { granted in
                    DispatchQueue.main.async { notificationsAnswered = granted }
                }
            }
        }
    }

    private var granted: some View {
        Label("Allowed", systemImage: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(nsColor: .systemGreen))
    }

    private var changeInSettings: some View {
        Text("Change in System Settings")
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondaryText)
    }

    private func permission<Action: View>(
        symbol: String, tint: NSColor, title: String, detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TintedIcon(symbolName: symbol, tint: Color(nsColor: tint), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.6), lineWidth: 1)
        )
    }
}

// MARK: - Done

private struct DonePage: View {
    let featureCount: Int

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(nsColor: .systemGreen))

            Text("You're all set")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Palette.primaryText)

            Text("Move the pointer to the notch at the top of the screen to try it.")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)

            Text(featureCount == 1 ? "1 feature is on." : "\(featureCount) features are on.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiaryText)

            Text("Change your mind about anything in Settings. To see this again, use Advanced › Show Welcome Again.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity)
    }
}
