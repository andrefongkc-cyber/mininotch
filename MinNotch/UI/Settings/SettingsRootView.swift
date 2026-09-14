import SwiftUI

/// The Settings window: sidebar on the left, one detail pane on the right.
///
/// The sidebar searches. Typing two or more characters swaps the pane list for matching
/// panes and rows; choosing a row opens its pane, scrolls to it, and flashes it. The panes
/// themselves know nothing about search: they read `settingsSearchTarget` from the
/// environment through `SettingsPane` and `SettingsRow`, so a new row is searchable the moment
/// it is in the index, with no per-pane code.
struct SettingsRootView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selection: SettingsTab

    @State private var query: String
    @State private var searchTarget: SettingsSearchTarget?
    @FocusState private var isSearchFocused: Bool

    init(initialTab: SettingsTab = .general, initialQuery: String = "") {
        _selection = State(initialValue: initialTab)
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .frame(minWidth: 460)
                .environment(\.settingsSearchTarget, searchTarget)
        }
        .navigationSplitViewStyle(.balanced)
        // ⌘F, as in every other Mac app with a search field. Hidden rather than a menu item
        // because this accessory app has no menu bar of its own to put one in.
        .background(
            Button("Search Settings") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    // MARK: Sidebar

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Search takes over the sidebar from two characters. One matches most of the list, which
    /// is noise rather than a search, so a single letter keeps the panes on screen.
    private var isSearching: Bool { trimmedQuery.count >= 2 }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 8)

            if isSearching {
                results
            } else {
                paneList
            }
        }
        .navigationSplitViewColumnWidth(
            min: Metrics.sidebarMinWidth,
            ideal: Metrics.sidebarIdealWidth,
            max: 260
        )
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)

            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .focused($isSearchFocused)
                // Return takes the best match, so a search is type-and-go.
                .onSubmit { if let first = matchingEntries.first { choose(first) } }
                .onExitCommand { query = "" }

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.separator.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isSearchFocused ? Palette.controlAccent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
    }

    private var paneList: some View {
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
    }

    // MARK: Results

    private var matchingEntries: [SettingsSearchEntry] {
        SettingsSearchIndex.matches(trimmedQuery)
    }

    /// Panes whose own name matches, shown above the rows. Someone typing "timer" most likely
    /// wants the Timer pane, not a list of every row that happens to live in it.
    private var matchingTabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.matchesSearch(trimmedQuery) }
    }

    @ViewBuilder
    private var results: some View {
        let entries = matchingEntries
        let tabs = matchingTabs

        if entries.isEmpty && tabs.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.tertiaryText)
                Text("No settings match “\(trimmedQuery)”")
                    .font(Typography.helper)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List {
                if !tabs.isEmpty {
                    Section("Panes") {
                        ForEach(tabs) { tab in
                            Button { open(tab) } label: { row(for: tab) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !entries.isEmpty {
                    Section("Settings") {
                        ForEach(entries) { entry in
                            Button { choose(entry) } label: { resultRow(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func resultRow(_ entry: SettingsSearchEntry) -> some View {
        let isChosen = searchTarget?.tab == entry.tab && searchTarget?.title == entry.title

        return HStack(spacing: 8) {
            SidebarIcon(tab: entry.tab)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Text(entry.section.isEmpty ? entry.tab.title : "\(entry.tab.title) › \(entry.section)")
                    .font(Typography.helper)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isChosen ? Palette.selectionTint.opacity(0.35) : .clear)
        )
        .contentShape(Rectangle())
        .help(entry.subtitle.isEmpty ? entry.title : entry.subtitle)
    }

    private func open(_ tab: SettingsTab) {
        selection = tab
        searchTarget = nil
    }

    /// Opens the entry's pane and points the pane at its row.
    ///
    /// The target is cleared again afterwards, so leaving the pane and coming back later does
    /// not replay the scroll and flash as though a search had just happened.
    private func choose(_ entry: SettingsSearchEntry) {
        selection = entry.tab
        let target = SettingsSearchTarget(tab: entry.tab, title: entry.title)
        searchTarget = target

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if searchTarget?.token == target.token { searchTarget = nil }
        }
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
