import SwiftUI

/// The Calendar widget: a mini week or month grid above a list of what is coming up.
struct CalendarWidgetView: View {
    @Bindable var viewModel: NotchViewModel

    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    @State private var quickAddText = ""
    @State private var quickAddKind: CalendarService.QuickAddKind = .event
    @FocusState private var isQuickAddFocused: Bool

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
            .onAppear { service.refreshReminders() }
        } else {
            permissionPrompt
        }
    }

    // MARK: Grid

    private var grid: some View {
        VStack(spacing: 5) {
            HStack {
                Text(monthTitle)
                    .font(Typography.bodyEmphasised)
                    .foregroundStyle(.white)
                Spacer()
                Text(todayTitle)
                    .font(Typography.helper)
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 0) {
                ForEach(Array(service.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }

            let days = service.days(for: settings.calendar.viewMode)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(days) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        VStack(spacing: 1) {
            Text("\(day.dayNumber)")
                .font(.system(size: 11, weight: day.isToday ? .bold : .regular))
                .foregroundStyle(dayColor(day))
                .frame(width: 20, height: 18)
                .background(
                    Circle()
                        .fill(day.isToday ? settings.appearance.resolvedAccent : .clear)
                        .frame(width: 20, height: 20)
                )

            Circle()
                .fill(day.hasEvents ? Color.white.opacity(0.55) : .clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayColor(_ day: CalendarDay) -> Color {
        if day.isToday { return .white }
        return .white.opacity(day.isInDisplayedMonth ? 0.8 : 0.3)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMy")
        return formatter.string(from: Date())
    }

    private var todayTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEd")
        return formatter.string(from: Date())
    }

    // MARK: Events

    private var eventList: some View {
        let items = Array(service.upcomingItems().prefix(settings.calendar.maxVisibleEvents))

        return Group {
            if items.isEmpty {
                Text("No upcoming events")
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

    private func subtitle(for item: CalendarItem) -> String {
        let time = item.timeDescription(using: Self.timeFormatter)
        let day = Calendar.current.isDateInToday(item.start)
            ? ""
            : Self.dayFormatter.string(from: item.start) + " · "
        let location = item.location.map { " · \($0)" } ?? ""
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

            TextField("Add \(quickAddKind.title.lowercased())…", text: $quickAddText)
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

    private func submitQuickAdd() {
        guard service.quickAdd(quickAddText, kind: quickAddKind) else { return }
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
