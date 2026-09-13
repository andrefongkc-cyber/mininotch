import EventKit
import SwiftUI

/// One event, flattened out of EventKit so views never touch `EKEvent` directly.
///
/// Keeping the view layer off EventKit types means the mini calendar can be previewed and
/// tested with sample data, and a future Reminders source can produce the same row type.
struct CalendarItem: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarIdentifier: String
    var calendarTitle: String
    var color: Color
    var location: String?
    /// Set for reminders once that source lands; nil for events.
    var isCompleted: Bool?

    init(event: EKEvent) {
        // `eventIdentifier` repeats across occurrences of a recurring event, so the start
        // date is folded in to keep list identities stable and unique.
        let base = event.eventIdentifier ?? UUID().uuidString
        self.id = "\(base)|\(event.startDate?.timeIntervalSince1970 ?? 0)"
        self.title = event.title ?? "Untitled Event"
        self.start = event.startDate ?? Date()
        self.end = event.endDate ?? event.startDate ?? Date()
        self.isAllDay = event.isAllDay
        self.calendarIdentifier = event.calendar?.calendarIdentifier ?? ""
        self.calendarTitle = event.calendar?.title ?? ""
        self.color = event.calendar.map { Color(nsColor: NSColor(cgColor: $0.cgColor) ?? .systemBlue) } ?? .accentColor
        self.location = event.location?.isEmpty == false ? event.location : nil
        self.isCompleted = nil
    }

    /// Builds a row from a reminder, so the event list can show both without knowing which
    /// is which. A reminder with no due date is not representable here and is filtered out
    /// before this point.
    init?(reminder: EKReminder) {
        guard let components = reminder.dueDateComponents,
              let due = Calendar.current.date(from: components) else { return nil }

        self.id = "reminder|" + (reminder.calendarItemIdentifier)
        self.title = reminder.title ?? "Untitled Reminder"
        self.start = due
        self.end = due
        // A reminder is a moment, not a span, so it is never all-day even when undated in
        // the time sense; the list renders it with its due time.
        self.isAllDay = components.hour == nil && components.minute == nil
        self.calendarIdentifier = reminder.calendar?.calendarIdentifier ?? ""
        self.calendarTitle = reminder.calendar?.title ?? ""
        self.color = reminder.calendar.map { Color(nsColor: NSColor(cgColor: $0.cgColor) ?? .systemBlue) } ?? .accentColor
        self.location = nil
        self.isCompleted = reminder.isCompleted
    }

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarIdentifier: String,
        calendarTitle: String,
        color: Color,
        location: String? = nil,
        isCompleted: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
        self.color = color
        self.location = location
        self.isCompleted = isCompleted
    }

    /// True for rows that came from Reminders rather than Calendar.
    var isReminder: Bool { isCompleted != nil }

    var isInProgress: Bool {
        let now = Date()
        return !isAllDay && start <= now && end > now
    }

    var isPast: Bool { end < Date() }

    /// "09:30", or "All day" for all-day items.
    func timeDescription(using formatter: DateFormatter) -> String {
        isAllDay ? "All day" : formatter.string(from: start)
    }
}

/// A calendar the user can show or hide in Settings > Calendar.
struct CalendarInfo: Identifiable, Equatable {
    let id: String
    var title: String
    var color: Color
    /// Account the calendar belongs to, e.g. "iCloud", used to group the settings list.
    var sourceTitle: String
    var allowsModification: Bool

    init(calendar: EKCalendar) {
        self.id = calendar.calendarIdentifier
        self.title = calendar.title
        self.color = Color(nsColor: NSColor(cgColor: calendar.cgColor) ?? .systemBlue)
        self.sourceTitle = calendar.source?.title ?? "Other"
        self.allowsModification = calendar.allowsContentModifications
    }
}

/// One cell in the mini calendar grid.
struct CalendarDay: Identifiable, Equatable {
    var date: Date
    var dayNumber: Int
    var isToday: Bool
    /// False for the leading and trailing days that pad a month grid.
    var isInDisplayedMonth: Bool
    var hasEvents: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}
