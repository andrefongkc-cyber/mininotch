import SwiftUI

struct AboutSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
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

                Text("MinNotch")
                    .font(.system(size: 20, weight: .bold))

                Text("Version \(version) (\(build))")
                    .font(Typography.helper)
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            SettingsCard(header: "What's New") {
                SettingsRow(
                    title: "Release Notes",
                    subtitle: "An in-app changelog arrives with the first update.",
                    systemImage: "sparkles",
                    badge: .comingSoon
                ) {
                    EmptyView()
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

            SettingsCard(header: "MinNotch") {
                SettingsRow(
                    title: "Quit MinNotch",
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
