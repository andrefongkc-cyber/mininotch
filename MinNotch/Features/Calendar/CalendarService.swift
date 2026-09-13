import EventKit
import Observation
import SwiftUI

/// Reads events from the system Calendar.
///
/// macOS 14 split calendar access into full and write-only, so this asks for full access
/// and treats `.writeOnly` as "not usable", since a read-only widget is the whole point.
/// The store posts `EKEventStoreChanged` on any edit anywhere, so the widget stays current
/// without polling.
@Observable
final class CalendarService {
    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var calendars: [CalendarInfo] = []
    /// Events in the visible window, already filtered by the user's hidden-calendar set.
    private(set) var items: [CalendarItem] = []
    /// Days with at least one event, used to draw the dot under a date in the grid.
    private(set) var daysWithEvents: Set<Date> = []
    private(set) var lastRefresh: Date?

    /// Reminders are a separate permission from events, and a separate store query, so they
    /// get their own status rather than being folded into the calendar one.
    private(set) var remindersAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var reminders: [CalendarItem] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshTimer: Timer?

    init() {}

    var hasAccess: Bool { authorizationStatus == .fullAccess }

    // MARK: Lifecycle

    func start(settings: SettingsStore) {
        self.settings = settings
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        remindersAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
            self?.refreshReminders()
        }

        // Events do not change on a timer, but "today", "in progress", and the upcoming
        // window all move, so a slow refresh keeps the list honest.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        if hasAccess { refresh() }
        refreshReminders()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
    }

    /// Prompts for calendar access. Safe to call when already granted or denied.
    ///
    /// The app has to be frontmost first. MinNotch is an accessory app with no Dock icon,
    /// and the notch panel is a non-activating panel specifically so that clicking it never
    /// steals focus, which means nothing here ever becomes the active app on its own. A TCC
    /// prompt raised by an app that is not frontmost is not reliably shown: the request
    /// resolves with `granted == false` and the status stays `notDetermined`, which looks
    /// exactly like a user who dismissed a dialog they never actually saw.
    ///
    /// Switching to a regular activation policy for the duration is what actually makes the
    /// dialog appear. It is restored as soon as the user answers, so the Dock icon appears
    /// only while the prompt is up.
    func requestAccess(completion: ((Bool) -> Void)? = nil) {
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)

        // If the callback never arrives the app would keep a Dock icon it should not have,
        // so the policy is restored on a timer regardless of what the request does.
        var didRestore = false
        func restorePolicy() {
            guard wasAccessory, !didRestore else { return }
            didRestore = true
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { restorePolicy() }

        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                restorePolicy()
                guard let self else { return }

                if let error {
                    AppLog.calendar.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
                }
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)

                if granted {
                    self.refresh()
                } else if self.authorizationStatus == .notDetermined {
                    // No dialog was shown and nothing was decided. Sending the user to the
                    // Privacy pane is the only remaining route.
                    AppLog.calendar.error("Calendar prompt did not appear; directing to System Settings")
                    self.promptDidNotAppear = true
                }

                completion?(granted)
            }
        }
    }

    /// Set when a request completed without the system ever showing a dialog, so the UI can
    /// stop offering a button that visibly does nothing.
    private(set) var promptDidNotAppear = false

    /// Opens the Privacy pane so a denied user has somewhere to go.
    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    var hasRemindersAccess: Bool { remindersAuthorizationStatus == .fullAccess }

    /// Prompts for Reminders access, with the same activation dance events need.
    func requestRemindersAccess(completion: ((Bool) -> Void)? = nil) {
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)

        var didRestore = false
        func restorePolicy() {
            guard wasAccessory, !didRestore else { return }
            didRestore = true
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { restorePolicy() }

        store.requestFullAccessToReminders { [weak self] granted, error in
            DispatchQueue.main.async {
                restorePolicy()
                guard let self else { return }
                if let error {
                    AppLog.calendar.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
                }
                self.remindersAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
                if granted { self.refreshReminders() }
                completion?(granted)
            }
        }
    }

    /// Loads reminders due inside the same window the events use.
    ///
    /// `fetchReminders` is asynchronous even though the event query is not, so this
    /// republishes on its own rather than being folded into `refresh()`.
    func refreshReminders() {
        guard let settings, settings.calendar.showReminders, hasRemindersAccess else {
            if !reminders.isEmpty { reminders = [] }
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 45, to: start) ?? start
        let hideCompleted = settings.calendar.hideCompletedReminders

        let predicate = store.predicateForReminders(in: nil)
        store.fetchReminders(matching: predicate) { [weak self] found in
            let items = (found ?? [])
                .filter { !hideCompleted || !$0.isCompleted }
                .compactMap(CalendarItem.init(reminder:))
                .filter { $0.start >= start && $0.start < end }

            DispatchQueue.main.async {
                self?.reminders = items.sorted { $0.start < $1.start }
            }
        }
    }

    // MARK: Creating

    enum QuickAddKind: String, CaseIterable, Identifiable {
        case event
        case reminder

        var id: String { rawValue }
        var title: String { self == .event ? "Event" : "Reminder" }
        var symbolName: String { self == .event ? "calendar" : "checklist" }
    }

    /// Creates an event or reminder from a title typed into the notch.
    ///
    /// Events land in the default calendar starting at the next half hour and lasting an
    /// hour, which is the least surprising thing to do with a bare title. Reminders are due
    /// at the same moment.
    @discardableResult
    func quickAdd(_ title: String, kind: QuickAddKind) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        let bump = minute < 30 ? 30 - minute : 60 - minute
        let start = calendar.date(byAdding: .minute, value: bump, to: now) ?? now

        do {
            switch kind {
            case .event:
                guard hasAccess, let target = store.defaultCalendarForNewEvents else { return false }
                let event = EKEvent(eventStore: store)
                event.title = trimmed
                event.startDate = start
                event.endDate = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
                event.calendar = target
                try store.save(event, span: .thisEvent, commit: true)
                refresh()

            case .reminder:
                guard hasRemindersAccess, let target = store.defaultCalendarForNewReminders() else { return false }
                let reminder = EKReminder(eventStore: store)
                reminder.title = trimmed
                reminder.calendar = target
                reminder.dueDateComponents = calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: start
                )
                try store.save(reminder, commit: true)
                refreshReminders()
            }
            return true
        } catch {
            AppLog.calendar.error("Quick add failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Loading

    func refresh() {
        guard hasAccess, let settings else { return }

        calendars = store.calendars(for: .event)
            .map(CalendarInfo.init)
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }

        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)

        // Fetch a whole month regardless of the selected view, so the month grid's dots and
        // the upcoming list come from one query.
        let windowEnd = calendar.date(byAdding: .day, value: 45, to: start) ?? start

        let hidden = settings.calendar.hiddenCalendarIdentifiers
        let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }

        guard !visible.isEmpty else {
            items = []
            daysWithEvents = []
            lastRefresh = now
            return
        }

        let predicate = store.predicateForEvents(withStart: start, end: windowEnd, calendars: visible)
        let events = store.events(matching: predicate)

        var loaded = events.map(CalendarItem.init)
        if !settings.calendar.showAllDayEvents {
            loaded.removeAll { $0.isAllDay }
        }
        loaded.sort { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
            return lhs.start < rhs.start
        }

        items = loaded
        daysWithEvents = Set((loaded + reminders).map { calendar.startOfDay(for: $0.start) })
        lastRefresh = now
    }

    // MARK: Queries used by the widget

    /// Events starting today, including any already in progress.
    func todayItems() -> [CalendarItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return items.filter { calendar.isDate($0.start, inSameDayAs: today) }
    }

    /// Today's remaining events followed by the next few days, capped for the panel.
    func upcomingItems() -> [CalendarItem] {
        guard let settings else { return [] }
        let calendar = Calendar.current
        let now = Date()
        let horizon = calendar.date(
            byAdding: .day,
            value: max(1, settings.calendar.upcomingDayCount),
            to: calendar.startOfDay(for: now)
        ) ?? now

        let merged = items + (settings.calendar.showReminders ? reminders : [])

        return merged
            .filter { $0.end >= now && $0.start < horizon }
            .sorted { $0.start < $1.start }
            .prefix(max(1, settings.calendar.maxVisibleEvents) * 3)
            .map { $0 }
    }

    /// Marks a reminder done, or undoes that, straight from the notch list.
    func setReminderCompleted(_ item: CalendarItem, completed: Bool) {
        guard hasRemindersAccess, item.isReminder else { return }
        let identifier = String(item.id.dropFirst("reminder|".count))
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }

        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
            refreshReminders()
        } catch {
            AppLog.calendar.error("Could not update reminder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The next event that has not finished yet, shown in the collapsed pill.
    func nextItem() -> CalendarItem? {
        let now = Date()
        return items.first { $0.end >= now && !$0.isAllDay }
    }

    // MARK: Grid

    /// Builds the day cells for the current week or month.
    func days(for mode: CalendarViewMode, reference: Date = Date()) -> [CalendarDay] {
        var calendar = Calendar.current
        if settings?.calendar.forceMondayFirst == true { calendar.firstWeekday = 2 }

        let today = calendar.startOfDay(for: Date())
        let component: Set<Calendar.Component> = mode == .week
            ? [.yearForWeekOfYear, .weekOfYear]
            : [.year, .month]

        guard let interval = calendar.dateInterval(
            of: mode == .week ? .weekOfYear : .month,
            for: reference
        ) else { return [] }

        let referenceMonth = calendar.component(.month, from: reference)

        // Pad a month grid out to whole weeks so the columns line up under the weekday row.
        var cursor: Date
        var count: Int
        if mode == .week {
            cursor = interval.start
            count = 7
        } else {
            let weekday = calendar.component(.weekday, from: interval.start)
            let offset = (weekday - calendar.firstWeekday + 7) % 7
            cursor = calendar.date(byAdding: .day, value: -offset, to: interval.start) ?? interval.start
            let totalDays = calendar.dateComponents([.day], from: cursor, to: interval.end).day ?? 28
            count = Int(ceil(Double(totalDays + offset) / 7.0)) * 7
            count = max(count, 35)
        }
        _ = component

        return (0..<count).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: cursor) else { return nil }
            let startOfDay = calendar.startOfDay(for: date)
            return CalendarDay(
                date: startOfDay,
                dayNumber: calendar.component(.day, from: date),
                isToday: calendar.isDate(startOfDay, inSameDayAs: today),
                isInDisplayedMonth: mode == .week
                    || calendar.component(.month, from: date) == referenceMonth,
                hasEvents: daysWithEvents.contains(startOfDay)
            )
        }
    }

    /// Localised one-letter weekday headers in the user's week order.
    func weekdaySymbols() -> [String] {
        var calendar = Calendar.current
        if settings?.calendar.forceMondayFirst == true { calendar.firstWeekday = 2 }

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
}

#if DEBUG
extension CalendarService {
    /// Injects fixed events for offscreen design review, bypassing EventKit entirely so a
    /// preview render never triggers a permission prompt.
    func applySampleItems(settings: SettingsStore) {
        self.settings = settings
        authorizationStatus = .fullAccess

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        func item(_ title: String, hour: Int, minutes: Int, dayOffset: Int, color: NSColor, location: String? = nil) -> CalendarItem {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay
            let start = calendar.date(byAdding: .minute, value: hour * 60, to: day) ?? day
            let end = calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
            return CalendarItem(
                id: title,
                title: title,
                start: start,
                end: end,
                isAllDay: false,
                calendarIdentifier: "sample",
                calendarTitle: "Work",
                color: Color(nsColor: color),
                location: location
            )
        }

        let hour = calendar.component(.hour, from: now)
        items = [
            item("Design review", hour: hour, minutes: 45, dayOffset: 0, color: .systemBlue, location: "Studio"),
            item("Lunch with Priya", hour: hour + 2, minutes: 60, dayOffset: 0, color: .systemOrange),
            item("Sprint planning", hour: 10, minutes: 30, dayOffset: 1, color: .systemPurple),
            item("Dentist", hour: 15, minutes: 45, dayOffset: 2, color: .systemGreen, location: "Elmwood Clinic")
        ]
        daysWithEvents = Set(items.map { calendar.startOfDay(for: $0.start) })
        lastRefresh = now
    }
}
#endif
