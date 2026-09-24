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
    /// The link that joins this event's online meeting, if it has one. See `MeetingLink`.
    var joinURL: URL?
    /// Set for reminders once that source lands; nil for events.
    var isCompleted: Bool?
    /// A reminder with no due date. It has no place on a timeline, so it sorts after
    /// everything dated and the list says "No due date" instead of a time.
    var isUndated = false

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
        self.joinURL = MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        self.isCompleted = nil
    }

    /// Builds a row from a reminder, so the event list can show both without knowing which
    /// is which. A reminder with no due date gets `isUndated` and a date far in the future,
    /// which keeps every date comparison elsewhere honest without special-casing it.
    init(reminder: EKReminder) {
        let components = reminder.dueDateComponents
        let due = components.flatMap { Calendar.current.date(from: $0) }

        self.id = "reminder|" + (reminder.calendarItemIdentifier)
        self.title = reminder.title ?? "Untitled Reminder"
        self.start = due ?? .distantFuture
        self.end = due ?? .distantFuture
        self.isUndated = due == nil
        // A reminder is a moment, not a span, so it is never all-day even when undated in
        // the time sense; the list renders it with its due time.
        self.isAllDay = due != nil && components?.hour == nil && components?.minute == nil
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
        joinURL: URL? = nil,
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
        self.joinURL = joinURL
        self.isCompleted = isCompleted
    }

    /// True for rows that came from Reminders rather than Calendar.
    var isReminder: Bool { isCompleted != nil }

    var isInProgress: Bool {
        let now = Date()
        return !isAllDay && start <= now && end > now
    }

    var isPast: Bool { !isUndated && end < Date() }

    /// "09:30", "All day" for all-day items, or "No due date".
    func timeDescription(using formatter: DateFormatter) -> String {
        if isUndated { return "No due date" }
        return isAllDay ? "All day" : formatter.string(from: start)
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
    /// The day whose events the list below the grid is showing.
    var isSelected = false

    var id: TimeInterval { date.timeIntervalSince1970 }
}
