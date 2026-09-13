import SwiftUI

/// The Settings window: sidebar on the left, one detail pane on the right.
struct SettingsRootView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selection: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(minWidth: 460)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(Array(SettingsTab.groups.enumerated()), id: \.offset) { index, group in
                Section {
                    ForEach(group) { tab in
                        row(for: tab).tag(tab)
                    }
                } header: {
                    // The first group carries no header, matching System Settings.
                    if index > 0 { Text(" ").font(.system(size: 2)) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(
            min: Metrics.sidebarMinWidth,
            ideal: Metrics.sidebarIdealWidth,
            max: 260
        )
    }

    private func row(for tab: SettingsTab) -> some View {
        HStack(spacing: 8) {
            SidebarIcon(tab: tab)
            Text(tab.title)
                .font(Typography.body)
            Spacer(minLength: 4)
            if let badge = tab.badge, badge == .comingSoon {
                Circle()
                    .fill(Palette.tertiaryText)
                    .frame(width: 5, height: 5)
                    .help("Not built yet")
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .media: MediaSettingsView()
        case .calendar: CalendarSettingsView()
        case .huds: HUDSettingsView()
        case .battery: BatterySettingsView()
        case .shelf: ShelfSettingsView()
        case .timer: TimerSettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .advanced: AdvancedSettingsView()
        case .about: AboutSettingsView()
        }
    }
}
