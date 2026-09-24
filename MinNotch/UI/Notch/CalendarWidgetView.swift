import AppKit
import SwiftUI

/// The Calendar widget: a mini week or month grid above a list of what is coming up.
///
/// The arrows move the grid a week or a month at a time, and clicking a day lists what is on
/// it instead of what is coming up. Clicking the same day again, or Today, goes back.
struct CalendarWidgetView: View {
    @Bindable var viewModel: NotchViewModel

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    @State private var quickAddText = ""
    @State private var quickAddKind: CalendarService.QuickAddKind = .event
    @FocusState private var isQuickAddFocused: Bool

    /// Any date inside the week or month the grid is showing.
    @State private var reference = Date()
    /// The day the list is showing, or nil for the upcoming list.
    @State private var selectedDay: Date?

    #if DEBUG
    /// Set by `--capture-notch --calendar-step n --calendar-pick n`, since a capture cannot click:
    /// how many weeks or months to move the grid, and which day, counted from today, to pick.
    static var debugStep = 0
    static var debugPick: Int?
    #endif

    private var service: CalendarService { environment.calendarService }

    /// Height of the scrolling event list. A `ScrollView` has no ideal height of its own,
    /// so this has to be stated explicitly or the list lays out at zero.
    static let eventListHeight: CGFloat = 112

    /// Height the widget needs, excluding the panel's padding and tab strip.
    ///
    /// The event list is capped rather than sized to the row count: beyond four rows the
    /// panel would be taller than the useful part of the screen, so the list scrolls.
    /// Height of the quick add row, including the space above it.
    static let quickAddHeight: CGFloat = 34

    static func preferredHeight(mode: CalendarViewMode, showsQuickAdd: Bool) -> CGFloat {
        let title: CGFloat = 17
        let weekdayRow: CGFloat = 11
        let dayCell: CGFloat = 22
        let gridSpacing: CGFloat = 5
        let weekRows: CGFloat = mode == .month ? 6 : 1

        let grid = title + gridSpacing + weekdayRow + gridSpacing
            + weekRows * dayCell + (weekRows - 1) * 3

        let eventList = Self.eventListHeight
        let divider: CGFloat = 1
        let spacing: CGFloat = 10

        var height = grid + spacing + divider + spacing + eventList
        if showsQuickAdd { height += quickAddHeight }
        return height
    }

    var body: some View {
        if service.hasAccess {
            VStack(alignment: .leading, spacing: 10) {
                grid
                Divider().overlay(Color.white.opacity(0.12))
                eventList
                if showsQuickAdd { quickAddRow }
            }
            .onAppear {
                service.refreshReminders()
                #if DEBUG
                reference = service.shifted(Date(), by: Self.debugStep, mode: mode)
                if let pick = Self.debugPick {
                    selectedDay = Calendar.current.date(byAdding: .day, value: pick, to: Calendar.current.startOfDay(for: Date()))
                }
                #endif
            }
        } else {
            permissionPrompt
        }
    }

    // MARK: Grid

    private var mode: CalendarViewMode { settings.calendar.viewMode }

    /// Off today's week or month, or on a picked day: something to come back from.
    private var isAwayFromToday: Bool {
        selectedDay != nil || !service.isCurrentPeriod(reference, mode: mode)
    }

    private var grid: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(monthTitle)
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(.white)

                stepButton("chevron.left", help: mode == .week ? "Previous week" : "Previous month") {
                    step(by: -1)
                }
                stepButton("chevron.right", help: mode == .week ? "Next week" : "Next month") {
                    step(by: 1)
                }

                Spacer()

                if isAwayFromToday {
                    Button {
                        returnToToday()
                    } label: {
                        HStack(spacing: 4) {
                            if let selectedDay {
                                Text(Self.selectedFormatter.string(from: selectedDay))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Text("Today")
                                .fontWeight(.semibold)
                                .foregroundStyle(settings.appearance.resolvedAccent)
                        }
                        .font(Typography.helper)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Back to today")
                } else {
                    Text(todayTitle)
                        .font(Typography.helper)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(height: 17)

            HStack(spacing: 0) {
                ForEach(Array(service.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            let days = service.days(for: mode, reference: reference, selected: selectedDay)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(days) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 18, height: 17)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let accent = settings.appearance.resolvedAccent
        return Button {
            select(day)
        } label: {
            VStack(spacing: 1) {
                Text("\(day.dayNumber)")
                    .font(.system(size: 11, weight: day.isToday || day.isSelected ? .bold : .regular))
                    .foregroundStyle(dayColor(day))
                    .frame(width: 20, height: 18)
                    .background(
                        Circle()
                            .fill(day.isToday ? accent : (day.isSelected ? Color.white.opacity(0.16) : .clear))
                            .frame(width: 20, height: 20)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(day.isSelected && day.isToday ? Color.white.opacity(0.9) : .clear, lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                    )

                Circle()
                    .fill(day.hasEvents ? Color.white.opacity(0.55) : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Self.selectedFormatter.string(from: day.date))
    }

    private func dayColor(_ day: CalendarDay) -> Color {
        if day.isToday || day.isSelected { return .white }
        return .white.opacity(day.isInDisplayedMonth ? 0.8 : 0.3)
    }

    /// The month on show. A week that crosses into the next month is named by the month most
    /// of it is in, which is the one its middle day falls in.
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMy")
        guard mode == .week, let first = service.days(for: .week, reference: reference).first?.date else {
            return formatter.string(from: reference)
        }
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: 3, to: first) ?? reference)
    }

    private func step(by steps: Int) {
        reference = service.shifted(reference, by: steps, mode: mode)
        selectedDay = nil
    }

    /// Picks a day, or goes back to the upcoming list when it is already picked. A padding day
    /// from the next or previous month also moves the grid there.
    private func select(_ day: CalendarDay) {
        if day.isSelected {
            selectedDay = nil
            return
        }
        selectedDay = day.date
        if !day.isInDisplayedMonth { reference = day.date }
    }

    private func returnToToday() {
        reference = Date()
        selectedDay = nil
    }

    private static let selectedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    private var todayTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEd")
        return formatter.string(from: Date())
    }

    // MARK: Events

    private var eventList: some View {
        // A picked day lists that day; another week or month lists all of it; otherwise what
        // is coming up from now.
        let items: [CalendarItem]
        if let selectedDay {
            items = service.items(on: selectedDay)
        } else if !service.isCurrentPeriod(reference, mode: mode) {
            items = service.items(in: service.period(containing: reference, mode: mode))
        } else {
            items = Array(service.upcomingItems().prefix(settings.calendar.maxVisibleEvents))
        }

        return Group {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            eventRow(item)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.eventListHeight, alignment: .topLeading)
    }

    private func eventRow(_ item: CalendarItem) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(item.color)
                .frame(width: 3, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(item.isPast ? 0.45 : 0.92))
                    .strikethrough(item.isCompleted ?? false, color: .white.opacity(0.5))
                    .lineLimit(1)

                Text(subtitle(for: item))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if item.isReminder {
                Button {
                    service.setReminderCompleted(item, completed: !(item.isCompleted ?? false))
                } label: {
                    Image(systemName: (item.isCompleted ?? false) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            (item.isCompleted ?? false)
                                ? settings.appearance.resolvedAccent
                                : .white.opacity(0.4)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help((item.isCompleted ?? false) ? "Mark as not done" : "Mark as done")
            } else if let joinURL = item.joinURL, Self.isJoinable(item) {
                joinButton(joinURL)
            } else if item.isInProgress {
                Text("Now")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(settings.appearance.resolvedAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(settings.appearance.resolvedAccent.opacity(0.18)))
            }
        }
    }

    /// From fifteen minutes before a meeting until it ends, which is when anyone reaches for it.
    private static func isJoinable(_ item: CalendarItem, now: Date = Date()) -> Bool {
        item.start.timeIntervalSince(now) <= 15 * 60 && item.end > now
    }

    /// Opens the meeting. The link is https to a known meeting host, checked by `MeetingLink`
    /// when it was read, so it cannot be a local file or an app's custom scheme.
    private func joinButton(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Join", systemImage: "video.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(settings.appearance.resolvedAccent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Join the meeting at \(url.host ?? "its link")")
    }

    private var emptyMessage: String {
        if let selectedDay { return "Nothing on " + Self.selectedFormatter.string(from: selectedDay) }
        guard !service.isCurrentPeriod(reference, mode: mode) else { return "No upcoming events" }
        return mode == .week ? "Nothing that week" : "Nothing in \(monthTitle)"
    }

    private func subtitle(for item: CalendarItem) -> String {
        let time = item.timeDescription(using: Self.timeFormatter)
        // On a picked day every row is that day, so naming it again is noise.
        let day = item.isUndated || selectedDay != nil || Calendar.current.isDateInToday(item.start)
            ? ""
            : Self.dayFormatter.string(from: item.start) + " · "
        // A meeting's link often is its location, and a URL is no use as a subtitle when the
        // row already has a Join button.
        let location = item.location.flatMap { $0.contains("://") ? nil : " · \($0)" } ?? ""
        return day + time + location
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    // MARK: Quick add

    private var showsQuickAdd: Bool {
        settings.calendar.enabled && settings.calendar.enableQuickAdd
    }

    /// A title field and a kind picker.
    ///
    /// Focusing it activates the app. The panel is non-activating by design, which means it
    /// can take key status without MinNotch being frontmost, and keystrokes would go to
    /// whatever app actually is. Typing has to be the one place that rule bends.
    private var quickAddRow: some View {
        HStack(spacing: 8) {
            Image(systemName: quickAddKind.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))

            TextField(quickAddPlaceholder, text: $quickAddText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($isQuickAddFocused)
                .onSubmit(submitQuickAdd)

            Picker("", selection: $quickAddKind) {
                ForEach(CalendarService.QuickAddKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(isQuickAddFocused ? 0.14 : 0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            isQuickAddFocused = true
        }
        // Auto-close would otherwise take the panel away mid-sentence.
        .onChange(of: isQuickAddFocused) { _, focused in
            viewModel.isInteractionLocked = focused
        }
        .onDisappear { viewModel.isInteractionLocked = false }
        .animation(Motion.hover, value: isQuickAddFocused)
    }

    private var quickAddPlaceholder: String {
        let kind = quickAddKind.title.lowercased()
        guard let selectedDay, !Calendar.current.isDateInToday(selectedDay) else { return "Add \(kind)…" }
        return "Add \(kind) on \(Self.selectedFormatter.string(from: selectedDay))…"
    }

    private func submitQuickAdd() {
        guard service.quickAdd(quickAddText, kind: quickAddKind, on: selectedDay) else { return }
        quickAddText = ""
    }

    // MARK: Permission

    /// True once asking has stopped being useful, either because the user said no or because
    /// the system never showed the dialog. Offering a button that visibly does nothing is
    /// worse than sending the user somewhere they can actually change the answer.
    private var needsSystemSettings: Bool {
        service.authorizationStatus == .denied || service.promptDidNotAppear
    }

    private var permissionPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.4))

            Text("Calendar Access Needed")
                .font(Typography.bodyEmphasised)
                .foregroundStyle(.white.opacity(0.8))

            Text(needsSystemSettings
                 ? "Turn MinNotch on under Privacy & Security > Calendars."
                 : "MinNotch reads your events to show what is coming up. Nothing leaves your Mac.")
                .font(Typography.helper)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            Button(needsSystemSettings ? "Open Privacy Settings" : "Allow Access") {
                if needsSystemSettings {
                    service.openPrivacySettings()
                } else {
                    service.requestAccess()
                }
            }
            .buttonStyle(NotchAccentButtonStyle(accent: settings.appearance.resolvedAccent))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}
