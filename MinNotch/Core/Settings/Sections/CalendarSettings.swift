import Foundation

enum CalendarViewMode: String, Codable, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Current Week"
        case .month: return "Month"
        }
    }
}

/// Settings > Calendar.
struct CalendarSettings: Codable, Equatable {
    var enabled: Bool = true
    var viewMode: CalendarViewMode = .week

    /// Calendar identifiers the user has switched off. Storing the hidden set rather than
    /// the visible one means a newly added calendar shows up by default, which is what
    /// people expect.
    var hiddenCalendarIdentifiers: Set<String> = []

    var showAllDayEvents: Bool = true

    /// How many days ahead the "upcoming" list reaches.
    var upcomingDayCount: Int = 3

    /// Cap on rows in the event list before it scrolls.
    var maxVisibleEvents: Int = 6

    /// Start the week on the user's locale first weekday, or force Monday.
    var forceMondayFirst: Bool = false

    // MARK: V2 scaffolding

    var showReminders: Bool = false
    var hideCompletedReminders: Bool = true
    var enableQuickAdd: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.value(.enabled, true)
        viewMode = c.value(.viewMode, CalendarViewMode.week)
        hiddenCalendarIdentifiers = c.value(.hiddenCalendarIdentifiers, Set<String>())
        showAllDayEvents = c.value(.showAllDayEvents, true)
        upcomingDayCount = c.value(.upcomingDayCount, 3, in: 1...14)
        maxVisibleEvents = c.value(.maxVisibleEvents, 6, in: 2...12)
        forceMondayFirst = c.value(.forceMondayFirst, false)
        showReminders = c.value(.showReminders, false)
        hideCompletedReminders = c.value(.hideCompletedReminders, true)
        enableQuickAdd = c.value(.enableQuickAdd, false)
    }
}
