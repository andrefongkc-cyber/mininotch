import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private var updates: UpdateService { environment.updates }

    /// The version alone once the build number is the version, as it is from 0.7 on, rather
    /// than the same number twice.
    private var versionText: String {
        build == version ? "Version \(version)" : "Version \(version) (\(build))"
    }

    var body: some View {
        @Bindable var updates = updates

        SettingsPane(title: "About") {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.controlAccent.gradient)
                    .frame(width: 76, height: 76)
                    .overlay(
                        Image(systemName: "rectangle.topthird.inset.filled")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.white)
                    )

                Text("MiniNotch")
                    .font(.system(size: 20, weight: .bold))

                Text(versionText)
                    .font(Typography.helper)
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            SettingsCard(header: "What's New") {
                SettingsRow(
                    title: "Release Notes",
                    subtitle: "What changed in this version, and where to find it. Also shown once after each update.",
                    systemImage: "sparkles"
                ) {
                    Button("Show") { environment.whatsNew.present() }
                        .controlSize(.small)
                }
            }

            SettingsCard(
                header: "Updates",
                footer: "New versions come from MiniNotch's GitHub releases, and each one is checked against MiniNotch's signing key before it installs. Checking fetches one small file from GitHub and sends nothing about your Mac."
            ) {
                SettingsRow(
                    title: "Check for Updates",
                    subtitle: updates.isAvailable
                        ? "Look for a new version now. You can also do this from the menu bar icon."
                        : "Not in a development build, which Xcode keeps up to date.",
                    systemImage: "arrow.down.circle",
                    isEnabled: updates.isAvailable
                ) {
                    Button("Check Now") { updates.checkForUpdates() }
                        .controlSize(.small)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Check Automatically",
                    subtitle: "When there is a new version, it asks before installing.",
                    systemImage: "clock.arrow.circlepath",
                    isEnabled: updates.isAvailable
                ) {
                    SettingsToggle(isOn: $updates.checksAutomatically)
                }

                SettingsDivider()

                SettingsRow(
                    title: "New Versions",
                    subtitle: updates.installsAutomatically
                        ? "Installed without asking, once the notch is closed and no timer is running. What's New then lists what changed."
                        : "A window asks first, listing what is new, with Install, Remind Me Later and Skip.",
                    systemImage: "arrow.down.app",
                    isEnabled: updates.isAvailable && updates.checksAutomatically
                ) {
                    Picker("", selection: $updates.installsAutomatically) {
                        Text("Ask First").tag(false)
                        Text("Install Automatically").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsDivider()

                SettingsRow(
                    title: "How Often",
                    subtitle: "How long between checks. Every 3 hours unless you change it.",
                    systemImage: "timer",
                    isEnabled: updates.isAvailable && updates.checksAutomatically
                ) {
                    Picker("", selection: Binding(
                        // The nearest choice, in case the stored value is not one of them.
                        get: {
                            UpdateService.intervalChoices.min {
                                abs($0.seconds - updates.checkInterval) < abs($1.seconds - updates.checkInterval)
                            }?.seconds ?? UpdateService.defaultInterval
                        },
                        set: { updates.checkInterval = $0 }
                    )) {
                        ForEach(UpdateService.intervalChoices, id: \.seconds) { choice in
                            Text(choice.title).tag(choice.seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            SettingsCard(header: "System") {
                SettingsRow(title: "macOS", systemImage: "desktopcomputer") {
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                        .font(Typography.helper)
                        .foregroundStyle(Palette.secondaryText)
                }

                SettingsDivider()

                SettingsRow(title: "Displays", systemImage: "display") {
                    Text(displayDescription)
                        .font(Typography.helper)
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            SettingsCard(header: "MiniNotch") {
                SettingsRow(
                    title: "Quit MiniNotch",
                    subtitle: "The notch and the menu bar icon both disappear until you launch it again.",
                    systemImage: "power"
                ) {
                    Button("Quit") { environment.quit() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var displayDescription: String {
        let screens = NSScreen.screens
        let notched = screens.filter { $0.safeAreaInsets.top > 0 }.count
        let plural = screens.count == 1 ? "display" : "displays"
        guard notched > 0 else { return "\(screens.count) \(plural), none notched" }
        return "\(screens.count) \(plural), \(notched) notched"
    }
}
