import Foundation

/// A tab in the expanded notch panel.
///
/// Adding a V2 widget means adding a case here, a row in `NotchWidgetRegistry`, and a view
/// in `ExpandedPanelView.content(for:)`. Nothing else has to change, and the raw values are
/// stable so a persisted `lastTab` survives new cases being added around it.
enum NotchTab: String, Codable, CaseIterable, Identifiable {
    case media
    case calendar
    case system
    case shelf
    case clipboard
    case links
    case timer
    case weather

    var id: String { rawValue }

    /// The tab this one is drawn in. Links is a feature but no longer a tab: it shares the Shelf
    /// tab with the files. The case stays so saved arrangements and a remembered tab still
    /// decode, and anything that asks for Links is sent to the Shelf.
    var panelTab: NotchTab { self == .links ? .shelf : self }

    var title: String {
        switch self {
        case .media: return "Now Playing"
        case .calendar: return "Calendar"
        case .system: return "System"
        case .shelf: return "Shelf"
        case .clipboard: return "Clipboard"
        case .links: return "Links"
        case .timer: return "Timer"
        case .weather: return "Weather"
        }
    }

    var symbolName: String {
        switch self {
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .system: return "gauge.with.dots.needle.33percent"
        case .shelf: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .links: return "link"
        case .timer: return "timer"
        case .weather: return "cloud.sun"
        }
    }
}
