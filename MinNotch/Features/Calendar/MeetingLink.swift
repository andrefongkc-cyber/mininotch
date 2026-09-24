import Foundation

/// Finds the link that joins an online meeting, in the places calendars put one.
///
/// Zoom, Meet and Teams each write their link somewhere different: the event's URL field, its
/// location, or the notes, often among a paragraph of dial-in numbers. So every field is searched
/// with a link detector, and the first link to a known meeting service wins.
///
/// Only https, and only these hosts. The link is handed to `NSWorkspace.open`, which opens
/// whatever a scheme is registered to, and a calendar invitation is text anyone can send: a
/// `file:` or custom-scheme link in an invite must never be one click from running.
enum MeetingLink {
    static let hosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "facetime.apple.com"
    ]

    /// The first meeting link in any of `fields`, in order.
    static func find(in fields: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        for field in fields {
            guard let field, !field.isEmpty else { continue }
            let range = NSRange(field.startIndex..., in: field)
            for match in detector.matches(in: field, range: range) {
                if let url = match.url, isMeeting(url) { return url }
            }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
